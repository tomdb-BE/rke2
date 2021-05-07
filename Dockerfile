ARG KUBERNETES_VERSION=dev
ARG K3S_VERSION=${KUBERNETES_VERSION}-k3s1
ARG GOLANG_VERSION=1.16.3
ARG BASE_IMAGE=alpine
ARG CALICO_BIRD_VERSION=v0.3.3

FROM ${BASE_IMAGE} AS base
RUN apk --update --no-cache add ca-certificates

FROM library/golang:${GOLANG_VERSION}-alpine AS goboring
ARG GOBORING_BUILD=7
RUN apk --no-cache add \
    bash \
    g++
ADD https://go-boringcrypto.storage.googleapis.com/go${GOLANG_VERSION}b${GOBORING_BUILD}.src.tar.gz /usr/local/boring.tgz
WORKDIR /usr/local/boring
RUN tar xzf ../boring.tgz
WORKDIR /usr/local/boring/go/src
RUN /bin/bash -c /usr/local/boring/go/src/make.bash
COPY scripts-boring/ /usr/local/boring/go/bin/

FROM library/golang:${GOLANG_VERSION}-alpine AS trivy
ARG TRIVY_VERSION=0.17.2
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
RUN apk --no-cache --update add \
    bash \
    binutils-gold \
    btrfs-progs-dev \
    btrfs-progs-static \
    coreutils \
    curl \
    docker \
    file \
    g++ \
    gcc \
    git \
    libseccomp-dev \
    libseccomp-static \
    libselinux-dev \
    linux-headers \
    make \
    mercurial \
    py-pip \
    rsync \
    subversion \
    tar \
    unzip \
    wget
RUN rm -fr /usr/local/go/*
COPY --from=goboring /usr/local/boring/go/ /usr/local/go/
COPY --from=trivy /usr/local/bin/ /usr/bin/
RUN set -x \
 && chmod -v +x /usr/local/go/bin/go*.sh \
 && go version \
 && trivy --download-db-only --quiet

# Dapper/Drone/CI environment
FROM build AS dapper
ENV DAPPER_ENV GODEBUG REPO TAG DRONE_TAG PAT_USERNAME PAT_TOKEN KUBERNETES_VERSION DOCKER_BUILDKIT DRONE_BUILD_EVENT IMAGE_NAME GCLOUD_AUTH ENABLE_REGISTRY TRIVY_VERSION BASE_IMAGE GOLANG_VERSION GOBORING_BUILD ETCD_VERSION PAUSE_VERSION RUNC_VERSION CRICTL_VERSION PROTOC_VERSION CONTAINERD_VERSION METRICS_SERVER_VERSION COREDNS_VERSION K3S_VERSION K3S_ROOT_VERSION FLANNEL_VERSION CALICO_VERSION CALICO_BPFTOOL_VERSION CALICO_BIRD_VERSION CNI_PLUGINS_VERSION HELM_VERSION NGINX_INGRESS_VERSION NGINX_INGRESS_DEFAULT_BACKEND_VERSION CILIUM_VERSION CILIUM_STARTUP_SCRIPT
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

FROM base AS kubernetes
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
# setup required packages
RUN set -x
ARG ARCH
ARG PROTOC_VERSION=3.11.4
RUN archurl=x86_64; if [[ "$ARCH" == "arm64" ]]; then archurl=aarch_64; fi; wget https://github.com/google/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-${archurl}.zip
RUN archurl=x86_64; if [[ "$ARCH" == "arm64" ]]; then archurl=aarch_64; fi; unzip protoc-${PROTOC_VERSION}-linux-${archurl}.zip -d /usr
# setup containerd build
ARG SRC="github.com/rancher/containerd"
ARG PKG="github.com/containerd/containerd"
ARG TAG="v1.4.4-k3s1"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
ENV GO_BUILDTAGS="apparmor,seccomp,selinux,static_build,netgo,osusergo"
ENV GO_BUILDFLAGS="-gcflags=-trimpath=${GOPATH}/src -tags=${GO_BUILDTAGS}"
RUN export GO_LDFLAGS="-linkmode=external \
    -X ${PKG}/version.Version=${TAG} \
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
FROM base AS containerd
ARG ARCH
ARG TAG
COPY --from=containerd-builder /usr/local/bin/ /usr/local/bin/

#Build crictl
FROM build AS crictl-builder
# setup required packages
RUN set -x
# setup the build
ARG PKG="github.com/kubernetes-sigs/cri-tools"
ARG SRC="github.com/kubernetes-sigs/cri-tools"
ARG TAG="v1.19.0"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
ENV GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.Version=${TAG}"
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/crictl ./cmd/crictl
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
RUN crictl --version
FROM base AS crictl
ARG ARCH
ARG TAG
COPY --from=crictl-builder /usr/local/bin/ /usr/local/bin/

#Build runc
FROM build AS runc-builder
# setup required packages
RUN set -x
# setup the build
ARG ARCH
ARG PKG="github.com/opencontainers/runc"
ARG SRC="github.com/opencontainers/runc"
ARG TAG="v1.0.0-rc93"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${RUNC_VERSION} -b ${RUNC_VERSION}
RUN BUILDTAGS='seccomp selinux apparmor' make static
RUN go-assert-static.sh runc
RUN install -s runc /usr/local/bin
RUN runc --version
FROM base AS runc
ARG ARCH
ARG TAG
COPY --from=runc-builder /usr/local/bin/ /usr/local/bin/

# rke-runtime image
# This image includes any host level programs that we might need. All binaries
# must be placed in bin/ of the file image and subdirectories of bin/ will be flattened during installation.
# This means bin/foo/bar will become bin/bar when rke2 installs this to the host
FROM rancher/k3s:${K3S_VERSION} AS k3s

FROM scratch AS runtime-collect
ARG ARCH
ARG TAG
ARG K3S_VERSION
ARG RUNC_VERSION
ARG CRICTL_VERSION
ARG CONTAINERD_VERSION
ARG KUBERNETES_VERSION
ARG CHARTS_VERSION
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
ARG ARCH
ARG TAG
ARG K3S_VERSION
ARG RUNC_VERSION
ARG CRICTL_VERSION
ARG CONTAINERD_VERSION
ARG KUBERNETES_VERSION
ARG CHARTS_VERSION
COPY --from=runtime-collect / /

#Build etcd
FROM build AS etcd-builder
ARG ARCH
ARG PKG=go.etcd.io/etcd
ARG SRC=github.com/rancher/etcd
ARG TAG="v3.4.13-k3s1"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
# build and assert statically linked executable(s)
RUN go mod vendor \
 && export GO_LDFLAGS="-linkmode=external -X ${PKG}/version.GitSHA=$(git rev-parse --short HEAD)" \
 && go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/etcd . \
 && go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/etcdctl ./etcdctl
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
ENV ETCD_UNSUPPORTED_ARCH=arm64
RUN etcd --version
FROM base AS runc
ARG ARCH
ARG TAG
ENV ETCD_UNSUPPORTED_ARCH=arm64
COPY --from=etcd-builder /usr/local/bin/ /usr/local/bin/

#Build coredns
FROM build AS coredns-builder
# setup the build
ARG ARCH
ARG SRC=github.com/coredns/coredns
ARG PKG=github.com/coredns/coredns
ARG TAG="v1.6.9"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN GO_LDFLAGS="-linkmode=external -X ${PKG}/coremain.GitCommit=$(git rev-parse --short HEAD)" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/coredns .
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
RUN coredns --version
FROM base AS coredns
ARG ARCH
ARG TAG
COPY --from=coredns-builder /usr/local/bin/coredns /coredns
ENTRYPOINT ["/coredns"]

#Build kube-proxy
FROM build AS kube-proxy-builder
RUN set -x
# setup the build
ARG ARCH
ARG K3S_ROOT_VERSION="v0.8.1"
ADD https://github.com/k3s-io/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-${ARCH}.tar /opt/k3s-root/k3s-root.tar
RUN tar xvf /opt/k3s-root/k3s-root.tar -C /opt/k3s-root --wildcards --strip-components=2 './bin/aux/*tables*'
RUN tar xvf /opt/k3s-root/k3s-root.tar -C /opt/k3s-root './bin/ipset'
ARG TAG="v1.18.8"
ARG PKG="github.com/kubernetes/kubernetes"
ARG SRC="github.com/kubernetes/kubernetes"
ARG MAJOR
ARG MINOR
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN GO_LDFLAGS="-linkmode=external \
    -X k8s.io/client-go/pkg/version.gitMajor=${MAJOR} \
    -X k8s.io/client-go/pkg/version.gitMinor=${MINOR} \
    -X k8s.io/component-base/version.gitMajor=${MAJOR} \
    -X k8s.io/component-base/version.gitMinor=${MINOR} \
    -X k8s.io/component-base/version.gitVersion=${TAG} \
    -X k8s.io/component-base/version.gitCommit=$(git rev-parse HEAD) \
    -X k8s.io/component-base/version.gitTreeState=clean \
    -X k8s.io/component-base/version.buildDate=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
    " go-build-static.sh -mod=vendor -gcflags=-trimpath=${GOPATH}/src -o bin/kube-proxy ./cmd/kube-proxy
RUN go-assert-static.sh bin/*
# install (with strip) to /usr/local/bin
RUN install -s bin/* /usr/local/bin
RUN kube-proxy --version
FROM base AS kube-proxy
ARG ARCH
ARG TAG
ARG K3S_ROOT_VERSION
RUN apk --no-cache add \
    conntrack-tools    \
    which
COPY --from=kube-proxy-builder /opt/k3s-root/aux/ /usr/sbin/
COPY --from=kube-proxy-builder /opt/k3s-root/bin/ /bin/
COPY --from=kube-proxy-builder /usr/local/bin/ /usr/local/bin/

#Build metrics-server
FROM build AS metrics-server-builder
ARG ARCH
ARG PKG="github.com/kubernetes-incubator/metrics-server"
ARG SRC="github.com/kubernetes-sigs/metrics-server"
ARG TAG="v0.4.4"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN go run vendor/k8s.io/kube-openapi/cmd/openapi-gen/openapi-gen.go --logtostderr \
    -i k8s.io/metrics/pkg/apis/metrics/v1beta1,k8s.io/apimachinery/pkg/apis/meta/v1,k8s.io/apimachinery/pkg/api/resource,k8s.io/apimachinery/pkg/version \
    -p ${PKG}/pkg/generated/openapi/ \
    -O zz_generated.openapi \
    -h $(pwd)/hack/boilerplate.go.txt \
    -r /dev/null
RUN GO_LDFLAGS="-linkmode=external \
    -X ${PKG}/pkg/version.Version=${TAG} \
    -X ${PKG}/pkg/version.gitCommit=$(git rev-parse HEAD) \
    -X ${PKG}/pkg/version.gitTreeState=clean \
    " \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/metrics-server ./cmd/metrics-server
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
RUN metrics-server --help
FROM base AS metrics-server
ARG ARCH
ARG TAG
COPY --from=metrics-server-builder /usr/local/bin/metrics-server /
ENTRYPOINT ["/metrics-server"]

FROM build AS k3s_xtables
ARG ARCH
ARG K3S_ROOT_VERSION="v0.8.1"
ADD https://github.com/rancher/k3s-root/releases/download/${K3S_ROOT_VERSION}/k3s-root-xtables-${ARCH}.tar /opt/xtables/k3s-root-xtables.tar
RUN tar xvf /opt/xtables/k3s-root-xtables.tar -C /opt/xtables

#Build flannel
FROM k3s_xtables AS flannel-builder
ARG ARCH
ARG TAG="v0.13.0-rancher1"
ARG PKG="github.com/coreos/flannel"
ARG SRC="github.com/rancher/flannel"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
# build and assert statically linked executable(s)
ENV GO_LDFLAGS="-X ${PKG}/version.Version=${TAG} -linkmode=external"
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/flanneld .
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
RUN flanneld --version
FROM base AS flannel
ARG ARCH
ARG TAG
ARG K3S_ROOT_VERSION="v0.8.1"
RUN apk --no-cache add             \
    ca-certificates                \
    strongswan net-tools which  && \
COPY --from=flannel-builder /opt/xtables/bin/ /usr/sbin/
COPY --from=flannel-builder /usr/local/bin/ /opt/bin/

FROM calico/bird:${CALICO_BIRD_VERSION}-${ARCH} AS calico_bird
### BEGIN CALICO BPFTOOL  #####
FROM debian:buster-slim as calico_bpftool
ARG ARCH
ARG CALICO_BPFTOOL_VERSION=v5.10
ARG KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
ARG KERNEL_REF=${CALICO_BPFTOOL_VERSION}
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        gpg gpg-agent libelf-dev libmnl-dev libc-dev iptables libgcc-8-dev \
        bash-completion binutils binutils-dev make git curl \
        ca-certificates xz-utils gcc pkg-config bison flex build-essential && \
    apt-get purge --auto-remove && \
    apt-get clean
WORKDIR /tmp
RUN git clone --depth 1 -b $KERNEL_REF $KERNEL_REPO
RUN cd linux/tools/bpf/bpftool/ && \
    sed -i '/CFLAGS += -O2/a CFLAGS += -static' Makefile && \
    sed -i 's/LIBS = -lelf $(LIBBPF)/LIBS = -lelf -lz $(LIBBPF)/g' Makefile && \
    printf 'feature-libbfd=0\nfeature-libelf=1\nfeature-bpf=1\nfeature-libelf-mmap=1' >> FEATURES_DUMP.bpftool && \
    FEATURES_DUMP=`pwd`/FEATURES_DUMP.bpftool make -j `getconf _NPROCESSORS_ONLN` && \
    strip bpftool && \
    ldd bpftool 2>&1 | grep -q -e "Not a valid dynamic program" \
        -e "not a dynamic executable" || \
        ( echo "Error: bpftool is not statically linked"; false ) && \
    mv bpftool /usr/bin && rm -rf /tmp/linux
### END CALICO BPFTOOL  ####
### BEGIN CALICOCTL ###
FROM build AS calico_ctl
ARG ARCH
ARG TAG="v3.18.3"
RUN git clone --depth=1 https://github.com/projectcalico/calicoctl.git $GOPATH/src/github.com/projectcalico/calicoctl
WORKDIR $GOPATH/src/github.com/projectcalico/calicoctl
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN GO_LDFLAGS="-linkmode=external \
    -X github.com/projectcalico/calicoctl/calicoctl/commands.VERSION=${TAG} \
    -X github.com/projectcalico/calicoctl/calicoctl/commands.GIT_REVISION=$(git rev-parse --short HEAD) \
    " go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/calicoctl ./calicoctl/calicoctl.go
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
RUN calicoctl --version
### END CALICOCTL #####
### BEGIN CALICO CNI ###
FROM build AS calico_cni
ARG TAG="v3.18.3"
RUN git clone --depth=1 https://github.com/projectcalico/cni-plugin.git $GOPATH/src/github.com/projectcalico/cni-plugin
WORKDIR $GOPATH/src/github.com/projectcalico/cni-plugin
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
ENV GO_LDFLAGS="-linkmode=external -X main.VERSION=${TAG}"
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/calico ./cmd/calico
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/calico-ipam ./cmd/calico-ipam
RUN go-assert-static.sh bin/*
RUN mkdir -vp /opt/cni/bin
RUN install -s bin/* /opt/cni/bin/
RUN install -m 0755 k8s-install/scripts/install-cni.sh /opt/cni/install-cni.sh
RUN install -m 0644 k8s-install/scripts/calico.conf.default /opt/cni/calico.conf.default
### END CALICO CNI #####
### BEGIN CALICO NODE ###
FROM build AS calico_node
ARG ARCH
ARG TAG="v3.18.3"
RUN git clone --depth=1 https://github.com/projectcalico/node.git $GOPATH/src/github.com/projectcalico/node
WORKDIR $GOPATH/src/github.com/projectcalico/node
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN GO_LDFLAGS="-linkmode=external \
    -X github.com/projectcalico/node/pkg/startup.VERSION=${TAG} \
    -X github.com/projectcalico/node/buildinfo.GitRevision=$(git rev-parse HEAD) \
    -X github.com/projectcalico/node/buildinfo.GitVersion=$(git describe --tags --always) \
    -X github.com/projectcalico/node/buildinfo.BuildDate=$(date -u +%FT%T%z) \
    " go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/calico-node ./cmd/calico-node
RUN go-assert-static.sh bin/*
RUN install -s bin/* /usr/local/bin
### END CALICO NODE #####
### BEGIN CALICO POD2DAEMON ###
FROM build AS calico_pod2daemon
ARG ARCH
ARG TAG="v3.18.3"
RUN git clone --depth=1 https://github.com/projectcalico/pod2daemon.git $GOPATH/src/github.com/projectcalico/pod2daemon
WORKDIR $GOPATH/src/github.com/projectcalico/pod2daemon
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
ENV GO_LDFLAGS="-linkmode=external"
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/flexvoldriver ./flexvol
RUN go-assert-static.sh bin/*
RUN install -m 0755 flexvol/docker/flexvol.sh /usr/local/bin/
RUN install -D -s bin/flexvoldriver /usr/local/bin/flexvol/flexvoldriver
### END CALICO POD2DAEMON #####
### BEGIN CNI PLUGINS ###
FROM build AS cni_plugins
ARG ARCH
ARG CNI_PLUGINS_VERSION="v0.9.1"
RUN git clone --depth=1 https://github.com/containernetworking/plugins.git $GOPATH/src/github.com/containernetworking/plugins
WORKDIR $GOPATH/src/github.com/containernetworking/plugins
RUN git fetch --all --tags --prune
RUN git checkout tags/${CNI_PLUGINS_VERSION} -b ${CNI_PLUGINS_VERSION}
RUN sh -ex ./build_linux.sh -v \
    -gcflags=-trimpath=/go/src \
    -ldflags " \
        -X github.com/containernetworking/plugins/pkg/utils/buildversion.BuildVersion=${CNI_PLUGINS_VERSION} \
        -linkmode=external -extldflags \"-static -Wl,--fatal-warnings\" \
    "
RUN go-assert-static.sh bin/*
# install (with strip) to /opt/cni/bin
RUN mkdir -vp /opt/cni/bin
RUN install -D -s bin/* /opt/cni/bin
### END CNI PLUGINS #####
# gather all of the disparate calico bits into a rootfs overlay
FROM scratch AS calico_rootfs_overlay
ARG ARCH
ARG TAG
ARG CNI_PLUGINS_VERSION
ARG CALICO_BPFTOOL_VERSION
ARG CALICO_BIRD_VERSION
ARG K3S_ROOT_VERSION
COPY --from=calico_node /go/src/github.com/projectcalico/node/filesystem/etc/       /etc/
COPY --from=calico_node /go/src/github.com/projectcalico/node/filesystem/licenses/  /licenses/
COPY --from=calico_node /go/src/github.com/projectcalico/node/filesystem/sbin/      /usr/sbin/
COPY --from=calico_node /usr/local/bin/         /usr/bin/
COPY --from=calico_ctl /usr/local/bin/calicoctl /calicoctl
COPY --from=calico_bird /bird*                  /usr/bin/
COPY --from=calico_bpftool /usr/bin/bpftool     /usr/sbin/
COPY --from=calico_pod2daemon /usr/local/bin/   /usr/local/bin/
COPY --from=calico_cni /opt/cni/                /opt/cni/
COPY --from=cni_plugins /opt/cni/               /opt/cni/
COPY --from=k3s_xtables /opt/xtables/bin/       /usr/sbin/
FROM base AS calico
ARG ARCH
ARG TAG
ARG CNI_PLUGINS_VERSION
ARG CALICO_BPFTOOL_VERSION
ARG CALICO_BIRD_VERSION
ARG K3S_ROOT_VERSION
RUN apk --no-cache add                         && \
    iptables conntrack-tools libcap               \
    ipset kmod iputils runit                      \
    procps net-tools conntrack-tools which 
COPY --from=calico_rootfs_overlay / /
ENV PATH=$PATH:/opt/cni/bin
RUN set -x \
 && test -e /opt/cni/install-cni.sh \
 && ln -vs /opt/cni/install-cni.sh /install-cni.sh \
 && test -e /opt/cni/calico.conf.default \
 && ln -vs /opt/cni/calico.conf.default /calico.conf.tmp

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
