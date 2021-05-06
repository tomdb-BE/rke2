ARG KUBERNETES_VERSION=dev
ARG BASE_IMAGE=alpine
ARG GOLANG_VERSION=1.16.2

FROM library/golang:${GOLANG_VERSION}-alpine AS goboring
ARG GOBORING_BUILD=5
RUN apk --no-cache add \
    bash \
    g++
ADD https://go-boringcrypto.storage.googleapis.com/go${GOLANG_VERSION}b${GOBORING_BUILD}.src.tar.gz /usr/local/boring.tgz
WORKDIR /usr/local/boring
RUN tar xzf ../boring.tgz
WORKDIR /usr/local/boring/go/src
RUN ./make.bash
COPY scripts/ /usr/local/boring/go/bin/

FROM library/golang:${GOLANG_VERSION}-alpine AS trivy
ARG TRIVY_VERSION=0.16.0
RUN set -ex; \
    if [ "$(go env GOARCH)" = "arm64" ]; then \
        wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz"; \
        tar -xzf trivy_${TRIVY_VERSION}_Linux-ARM64.tar.gz;  \
        mv trivy /usr/local/bin;                             \
    else                                                     \
        wget -q "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
        tar -xzf trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz;  \
        mv trivy /usr/local/bin;                             \
    fi

FROM library/golang:${GOLANG_VERSION}-alpine AS build
RUN apk --no-cache add \
    bash \
    binutils-gold \
    coreutils \
    curl \
    docker \
    file \
    g++ \
    gcc \
    git \
    libseccomp-dev \
    make \
    mercurial \
    py-pip \
    rsync \
    subversion \
    binutils-gold \
    wget
RUN rm -fr /usr/local/go/*
COPY --from=goboring /usr/local/boring/go/ /usr/local/go/
COPY --from=trivy /usr/local/bin/ /usr/bin/
RUN set -x \
 && chmod -v +x /usr/local/go/bin/go-*.sh \
 && go version \
 && trivy --download-db-only --quiet

# Dapper/Drone/CI environment
FROM build AS dapper
ENV DAPPER_ENV GODEBUG REPO TAG DRONE_TAG PAT_USERNAME PAT_TOKEN KUBERNETES_VERSION DOCKER_BUILDKIT DRONE_BUILD_EVENT IMAGE_NAME GCLOUD_AUTH ENABLE_REGISTRY TRIVY_VERSION
ARG DAPPER_HOST_ARCH
ENV ARCH $DAPPER_HOST_ARCH
ENV DAPPER_OUTPUT ./dist ./bin ./build
ENV DAPPER_DOCKER_SOCKET true
ENV DAPPER_TARGET dapper
ENV DAPPER_RUN_ARGS "--privileged --network host -v /tmp:/tmp -v rke2-pkg:/go/pkg -v rke2-cache:/root/.cache/go-build -v trivy-cache:/root/.cache/trivy"
RUN curl -sL https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubectl -o /usr/local/bin/kubectl && \
    chmod a+x /usr/local/bin/kubectl; \
    pip install codespell
RUN curl -sL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s v1.27.0
RUN set -x \
 && apk --no-cache add \
    libarchive-tools \
    zstd \
    jq \
    python2
WORKDIR /source
# End Dapper stuff

# Shell used for debugging
FROM dapper AS shell
RUN set -x \
 && apk --no-cache add \
    bash-completion \
    iptables \
    less \
    psmisc \
    rsync \
    socat \
    sudo \
    vim
RUN GO111MODULE=off GOBIN=/usr/local/bin go get github.com/go-delve/delve/cmd/dlv
RUN echo 'alias abort="echo -e '\''q\ny\n'\'' | dlv connect :2345"' >> /root/.bashrc
ENV PATH=/var/lib/rancher/rke2/bin:$PATH
ENV KUBECONFIG=/etc/rancher/rke2/rke2.yaml
ENV ETCD_UNSUPPORTED_ARCH=arm64
VOLUME /var/lib/rancher/rke2
# This makes it so we can run and debug k3s too
VOLUME /var/lib/rancher/k3s

FROM build AS build-k8s-codegen
ARG KUBERNETES_VERSION
RUN git clone -b ${KUBERNETES_VERSION} --depth=1 https://github.com/kubernetes/kubernetes.git ${GOPATH}/src/kubernetes
WORKDIR ${GOPATH}/src/kubernetes
# force code generation
RUN make WHAT=cmd/kube-apiserver
ARG TAG
ARG MAJOR
ARG MINOR
# build statically linked executables
RUN echo "export GIT_COMMIT=$(git rev-parse HEAD)" \
    >> /usr/local/go/bin/go-build-static-k8s.sh
RUN echo "export BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    >> /usr/local/go/bin/go-build-static-k8s.sh
RUN echo "export GO_LDFLAGS=\"-linkmode=external \
    -X k8s.io/component-base/version.gitVersion=${TAG} \
    -X k8s.io/component-base/version.gitMajor=${MAJOR} \
    -X k8s.io/component-base/version.gitMinor=${MINOR} \
    -X k8s.io/component-base/version.gitCommit=\${GIT_COMMIT} \
    -X k8s.io/component-base/version.gitTreeState=clean \
    -X k8s.io/component-base/version.buildDate=\${BUILD_DATE} \
    -X k8s.io/client-go/pkg/version.gitVersion=${TAG} \
    -X k8s.io/client-go/pkg/version.gitMajor=${MAJOR} \
    -X k8s.io/client-go/pkg/version.gitMinor=${MINOR} \
    -X k8s.io/client-go/pkg/version.gitCommit=\${GIT_COMMIT} \
    -X k8s.io/client-go/pkg/version.gitTreeState=clean \
    -X k8s.io/client-go/pkg/version.buildDate=\${BUILD_DATE} \
    \"" >> /usr/local/go/bin/go-build-static-k8s.sh
RUN echo 'go-build-static.sh -gcflags=-trimpath=${GOPATH}/src/kubernetes -mod=vendor -tags=selinux,osusergo,netgo ${@}' \
    >> /usr/local/go/bin/go-build-static-k8s.sh
RUN chmod -v +x /usr/local/go/bin/go-*.sh

FROM build-k8s-codegen AS build-k8s
RUN go-build-static-k8s.sh -o bin/kube-apiserver           ./cmd/kube-apiserver
RUN go-build-static-k8s.sh -o bin/kube-controller-manager  ./cmd/kube-controller-manager
RUN go-build-static-k8s.sh -o bin/kube-scheduler           ./cmd/kube-scheduler
RUN go-build-static-k8s.sh -o bin/kube-proxy               ./cmd/kube-proxy
RUN go-build-static-k8s.sh -o bin/kubeadm                  ./cmd/kubeadm
RUN go-build-static-k8s.sh -o bin/kubectl                  ./cmd/kubectl
RUN go-build-static-k8s.sh -o bin/kubelet                  ./cmd/kubelet
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin/
RUN kube-proxy --version

FROM ${BASE_IMAGE} AS kubernetes
RUN apk --update --no-cache add iptables
COPY --from=build-k8s \
    /usr/local/bin/ \
    /usr/local/bin/

FROM build AS charts
ARG CHART_REPO="https://rke2-charts.rancher.io"
ARG CACHEBUST="cachebust"
COPY charts/ /charts/
RUN echo ${CACHEBUST}>/dev/null
RUN CHART_VERSION="1.9.403"                   CHART_FILE=/charts/rke2-cilium.yaml         CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN CHART_VERSION="v3.13.300-build2021022303" CHART_FILE=/charts/rke2-canal.yaml          CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN CHART_VERSION="v3.18.1-102"               CHART_FILE=/charts/rke2-calico.yaml         CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN CHART_VERSION="v1.0.002"                  CHART_FILE=/charts/rke2-calico-crd.yaml     CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN CHART_VERSION="1.10.101-build2021022303"  CHART_FILE=/charts/rke2-coredns.yaml        CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN CHART_VERSION="1.36.301"                  CHART_FILE=/charts/rke2-ingress-nginx.yaml  CHART_BOOTSTRAP=false  /charts/build-chart.sh
RUN CHART_VERSION="v1.21.0-build2021041302"   CHART_FILE=/charts/rke2-kube-proxy.yaml     CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN CHART_VERSION="2.11.100-build2021022300"  CHART_FILE=/charts/rke2-metrics-server.yaml CHART_BOOTSTRAP=false  /charts/build-chart.sh
RUN CHART_VERSION="1.0.000"                   CHART_FILE=/charts/rancher-vsphere-cpi.yaml CHART_BOOTSTRAP=true   CHART_REPO="https://charts.rancher.io" /charts/build-chart.sh
RUN CHART_VERSION="2.1.000"                   CHART_FILE=/charts/rancher-vsphere-csi.yaml CHART_BOOTSTRAP=true   CHART_REPO="https://charts.rancher.io" /charts/build-chart.sh
RUN rm -vf /charts/*.sh /charts/*.md

#build containerd
FROM build AS containerd-builder
ARG PROTOC_VERSION=3.15.8
# setup required packages
RUN set -x \
 && apk --no-cache add \
    btrfs-progs-dev \
    btrfs-progs-static \
    file \
    gcc \
    git \
    libselinux-dev \
    libseccomp-dev \
    libseccomp-static \
    make \
    mercurial \
    subversion \
    unzip
RUN archurl=x86_64; if [[ $ARCH == "arm64" ]]; then archurl=aarch_64; fi; wget https://github.com/google/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-${archurl}.zip
RUN archurl=x86_64; if [[ $ARCH == "arm64" ]]; then archurl=aarch_64; fi; unzip protoc-${PROTOC_VERSION}-linux-${archurl}.zip -d /usr
# setup containerd build
ARG SRC="github.com/rancher/containerd"
ARG PKG="github.com/containerd/containerd"
ARG CONTAINERD_VERSION="v1.4.3-k3s3"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${CONTAINERD_VERSION} -b ${CONTAINERD_VERSION}
ENV GO_BUILDTAGS="apparmor,seccomp,selinux,static_build,netgo,osusergo"
ENV GO_BUILDFLAGS="-gcflags=-trimpath=${GOPATH}/src -tags=${GO_BUILDTAGS}"
RUN export GO_LDFLAGS="-linkmode=external \
    -X ${PKG}/version.Version=${CONTAINERD_VERSION} \
    -X ${PKG}/version.Package=${SRC} \
    -X ${PKG}/version.Revision=$(git rev-parse HEAD) \
    " \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/ctr                      ./cmd/ctr \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd               ./cmd/containerd \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-stress        ./cmd/containerd-stress \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim          ./cmd/containerd-shim \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim-runc-v1  ./cmd/containerd-shim-runc-v1 \
 && go-build-static.sh ${GO_BUILDFLAGS} -o bin/containerd-shim-runc-v2  ./cmd/containerd-shim-runc-v2
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
RUN containerd --version
FROM ${BASE_IMAGE} AS containerd
COPY --from=containerd-builder /usr/local/bin/ /usr/local/bin/

#Build crictl
FROM build AS crictl-builder
# setup required packages
RUN set -x \
 && apk --no-cache add \
    file \
    gcc \
    git \
    libselinux-dev \
    libseccomp-dev \
    make
# setup the build
ARG PKG="github.com/kubernetes-sigs/cri-tools"
ARG SRC="github.com/kubernetes-sigs/cri-tools"
ARG CRICTL_VERSION="v1.19.0"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${CRICTL_VERSION} -b ${CRICTL_VERSION}
ENV GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.Version=${CRICTL_VERSION}"
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/crictl ./cmd/crictl
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
RUN crictl --version
FROM ${BASE_IMAGE} AS crictl
COPY --from=crictl-builder /usr/local/bin/ /usr/local/bin/

#Build runc
FROM build AS runc-builder
# setup required packages
RUN set -x \
 && apk --no-cache add \
    file \
    gcc \
    git \
    libselinux-dev \
    libseccomp-dev \
    libseccomp-static \
    make
# setup the build
ARG PKG="github.com/opencontainers/runc"
ARG SRC="github.com/opencontainers/runc"
ARG RUNC_VERSION="v1.0.0-rc93"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${RUNC_VERSION} -b ${RUNC_VERSION}
RUN BUILDTAGS='seccomp selinux apparmor' make static
RUN go-assert-static.sh runc
RUN install -s runc /usr/local/bin
RUN runc --version
FROM ${BASE_IMAGE} AS runc
COPY --from=runc-builder /usr/local/bin/ /usr/local/bin/

# rke-runtime image
# This image includes any host level programs that we might need. All binaries
# must be placed in bin/ of the file image and subdirectories of bin/ will be flattened during installation.
# This means bin/foo/bar will become bin/bar when rke2 installs this to the host
FROM rancher/k3s:v1.21.0-k3s1 AS k3s
FROM rancher/hardened-runc:v1.0.0-rc93-build20210223 AS runc

FROM scratch AS runtime-collect
COPY --from=k3s \
    /bin/socat \
    /bin/
COPY --from=runc \
    /usr/local/bin/runc \
    /bin/
COPY --from=crictl \
    /usr/local/bin/crictl \
    /bin/
COPY --from=containerd \
    /usr/local/bin/containerd \
    /usr/local/bin/containerd-shim \
    /usr/local/bin/containerd-shim-runc-v1 \
    /usr/local/bin/containerd-shim-runc-v2 \
    /usr/local/bin/ctr \
    /bin/
COPY --from=kubernetes \
    /usr/local/bin/kubectl \
    /usr/local/bin/kubelet \
    /bin/
COPY --from=charts \
    /charts/ \
    /charts/

FROM scratch AS runtime
COPY --from=runtime-collect / /

FROM ubuntu:18.04 AS test
ARG TARGETARCH
VOLUME /var/lib/rancher/rke2
VOLUME /var/lib/kubelet
VOLUME /var/lib/cni
VOLUME /var/log
COPY bin/rke2 /bin/
# use built air-gap images
COPY build/images/rke2-images.tar /var/lib/rancher/rke2/agent/images/
COPY build/images.txt /images.txt
# use rke2 bundled binaries
ENV PATH=/var/lib/rancher/rke2/bin:$PATH
# for etcd arm64
ENV ETCD_UNSUPPORTED_ARCH=arm64
# for kubectl
ENV KUBECONFIG=/etc/rancher/rke2/rke2.yaml
# for crictl
ENV CONTAINER_RUNTIME_ENDPOINT="unix:///run/k3s/containerd/containerd.sock"
# for ctr
RUN mkdir -p /run/containerd \
    &&  ln -s /run/k3s/containerd/containerd.sock /run/containerd/containerd.sock
# for go dns bug
RUN mkdir -p /etc && \
    echo 'hosts: files dns' > /etc/nsswitch.conf
# for conformance testing
RUN chmod 1777 /tmp
RUN set -x \
 && export DEBIAN_FRONTEND=noninteractive \
 && apt-get -y update \
 && apt-get -y upgrade \
 && apt-get -y install \
    bash \
    bash-completion \
    ca-certificates \
    conntrack \
    ebtables \
    ethtool \
    iptables \
    jq \
    less \
    socat \
    vim
ENTRYPOINT ["/bin/rke2"]
CMD ["server"]
