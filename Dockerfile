ARG KUBERNETES_VERSION=dev
ARG K3S_VERSION
ARG KUBERNETES_IMAGE_TAG
ARG CONTAINERD_VERSION
ARG CRICTL_VERSION
ARG RUNC_VERSION
ARG REPO

# Build environment
FROM rancher/hardened-build-base:v1.16.6b7 AS build
RUN set -x \
    && apk --no-cache add \
    bash \
    curl \
    file \
    git \
    libseccomp-dev \
    rsync \
    gcc \
    bsd-compat-headers \
    binutils-gold \
    py-pip \
    pigz

# Dapper/Drone/CI environment
FROM build AS dapper
ENV DAPPER_ENV GODEBUG REPO TAG DRONE_TAG PAT_USERNAME PAT_TOKEN KUBERNETES_VERSION DOCKER_BUILDKIT DRONE_BUILD_EVENT IMAGE_NAME GCLOUD_AUTH ENABLE_REGISTRY IMAGE_BUILD_VERSION VERSION REGISTRY K3S_VERSION CONTAINERD_VERSION CRICTL_VERSION RUNC_VERSION KUBERNETES_VERSION KUBERNETES_IMAGE_TAG COREDNS_VERSION ETCD_VERSION METRICS_SERVER_VERSION PAUSE_VERSION KLIPPER_HELM_VERSION JETTECH_VERSION NGINX_INGRESS_VERSION NGINX_INGRESS_DEFAULT_BACKEND_VERSION KUBE_PROXY_VERSION CCM_VERSION CALICO_VERSION CALICO_OPERATOR_VERSION CALICO_CRD_VERSION FLANNEL_VERSION CILIUM_VERSION CILIUM_STARTUP_SCRIPT_VERSION MULTUS_VERSION CNI_PLUGINS_VERSION SRIOV_VERSION SRIOV_DEVICE_PLUGIN_VERSION SRIOV_CNI_VERSION SRIOV_RESOURCES_INJECTOR_VERSION VSPHERE_CPI_VERSION VSPHERE_CSI_VERSION K8SCSI_CSI_ATTACHER_VERSION K8SCSI_CSI_NODE_DRIVER_VERSION K8SCSI_CSI_PROVISIONER_VERSION K8SCSI_CSI_RESIZER_VERSION K8SCSI_CSI_LIVENESSPROBE_VERSION CILIUM_CHART_VERSION CANAL_CHART_VERSION CALICO_CHART_VERSION CALICO_CRD_CHART_VERSION COREDNS_CHART_VERSION NGINX_INGRESS_CHART_VERSION KUBE_PROXY_CHART_VERSION KUBE_PROXY_CHART_PACKAGE_VERSION METRICS_SERVER_CHART_VERSION MULTUS_CHART_VERSION VSPHERE_CPI_CHART_VERSION VSPHERE_CSI_CHART_VERSION
ARG DAPPER_HOST_ARCH
ENV ARCH $DAPPER_HOST_ARCH
ENV DAPPER_OUTPUT ./dist ./bin ./build
ENV DAPPER_DOCKER_SOCKET true
ENV DAPPER_TARGET dapper
ENV DAPPER_RUN_ARGS "--privileged --network host -v /tmp:/tmp -v rke2-pkg:/go/pkg -v rke2-cache:/root/.cache/go-build -v trivy-cache:/root/.cache/trivy"
RUN if [ "${ARCH}" = "amd64" ] || [ "${ARCH}" = "arm64" ]; then \
    VERSION=0.50.0 OS=linux && \
    curl -sL "https://github.com/vmware-tanzu/sonobuoy/releases/download/v${VERSION}/sonobuoy_${VERSION}_${OS}_${ARCH}.tar.gz" | \
    tar -xzf - -C /usr/local/bin; \
    fi
RUN curl -sL https://storage.googleapis.com/kubernetes-release/release/$( \
    curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt \
    )/bin/linux/${ARCH}/kubectl -o /usr/local/bin/kubectl && \
    chmod a+x /usr/local/bin/kubectl; \
    pip install codespell

RUN curl -sL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s v1.41.0
RUN set -x \
    && apk --no-cache add \
    libarchive-tools \
    zstd \
    jq \
    python2
RUN GOCR_VERSION="v0.5.1" && \
    if [ "${ARCH}" = "arm64" ]; then \
    wget https://github.com/google/go-containerregistry/releases/download/${GOCR_VERSION}/go-containerregistry_Linux_arm64.tar.gz && \
    tar -zxvf go-containerregistry_Linux_arm64.tar.gz && \
    mv crane /usr/local/bin && \
    chmod a+x /usr/local/bin/crane; \
    else \
    wget https://github.com/google/go-containerregistry/releases/download/${GOCR_VERSION}/go-containerregistry_Linux_x86_64.tar.gz && \
    tar -zxvf go-containerregistry_Linux_x86_64.tar.gz && \
    mv crane /usr/local/bin && \
    chmod a+x /usr/local/bin/crane; \
    fi

RUN VERSION=0.16.0 && \
    if [ "${ARCH}" = "arm64" ]; then \
    wget https://github.com/aquasecurity/trivy/releases/download/v${VERSION}/trivy_${VERSION}_Linux-ARM64.tar.gz && \
    tar -zxvf trivy_${VERSION}_Linux-ARM64.tar.gz && \
    mv trivy /usr/local/bin; \
    else \
    wget https://github.com/aquasecurity/trivy/releases/download/v${VERSION}/trivy_${VERSION}_Linux-64bit.tar.gz && \
    tar -zxvf trivy_${VERSION}_Linux-64bit.tar.gz && \
    mv trivy /usr/local/bin; \
    fi
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
VOLUME /var/lib/rancher/rke2
# This makes it so we can run and debug k3s too
VOLUME /var/lib/rancher/k3s

FROM build AS charts
ARG CHART_REPO="https://rke2-charts.rancher.io"
ARG CACHEBUST="cachebust"
ARG CILIUM_VERSION
ARG CILIUM_STARTUP_SCRIPT_VERSION
ARG CALICO_VERSION
ARG CALICO_CRD_VERSION
ARG FLANNEL_VERSION
ARG COREDNS_VERSION
ARG CHART_TAG_ARCH
ARG NGINX_INGRESS_VERSION
ARG NGINX_INGRESS_DEFAULT_BACKEND_VERSION
ARG KUBE_PROXY_VERSION
ARG METRICS_SERVER_VERSION
ARG MULTUS_VERSION
ARG CNI_PLUGINS_VERSION
ARG VSPHERE_CPI_VERSION
ARG VSPHERE_CSI_VERSION
ARG CILIUM_CHART_VERSION
ARG CANAL_CHART_VERSION
ARG CALICO_CHART_VERSION
ARG CALICO_CRD_CHART_VERSION
ARG COREDNS_CHART_VERSION
ARG NGINX_INGRESS_CHART_VERSION
ARG KUBE_PROXY_CHART_VERSION
ARG KUBE_PROXY_CHART_PACKAGE_VERSION
ARG METRICS_SERVER_CHART_VERSION
ARG MULTUS_CHART_VERSION
ARG VSPHERE_CPI_CHART_VERSION
ARG VSPHERE_CSI_CHART_VERSION
ARG REPO

RUN apk add --no-cache gettext
COPY charts/ /charts/
RUN echo ${CACHEBUST}>/dev/null
RUN REPO=${REPO}/mirrored-cilium CHART_VERSION=${CILIUM_CHART_VERSION}                        CHART_TAG=${CILIUM_VERSION}           CHART_TAG_STARTUP=${CILIUM_STARTUP_SCRIPT_VERSION}           CHART_FILE=/charts/rke2-cilium.yaml         CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN REPO=${REPO} CHART_VERSION=${CANAL_CHART_VERSION}                         CHART_TAG=${CALICO_VERSION}           CHART_TAG_FLANNEL=${FLANNEL_VERSION}                         CHART_FILE=/charts/rke2-canal.yaml          CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN REPO=${REPO}/hardened-calico CHART_VERSION=${CALICO_CHART_VERSION}                        CHART_TAG=${CALICO_VERSION}                                                                        CHART_FILE=/charts/rke2-calico.yaml         CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN REPO=${REPO} CHART_VERSION=${CALICO_CRD_CHART_VERSION}                    CHART_TAG=${CALICO_CRD_VERSION}                                                                    CHART_FILE=/charts/rke2-calico-crd.yaml     CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN REPO=${REPO} CHART_VERSION=${COREDNS_CHART_VERSION}                       CHART_TAG=${COREDNS_VERSION}             CHART_FILE=/charts/rke2-coredns.yaml        CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN REPO=${REPO}/nginx-ingress-controller CHART_VERSION=${NGINX_INGRESS_CHART_VERSION}                 CHART_TAG=${NGINX_INGRESS_VERSION}    CHART_TAG_BACKEND=${NGINX_INGRESS_DEFAULT_BACKEND_VERSION}   CHART_FILE=/charts/rke2-ingress-nginx.yaml  CHART_BOOTSTRAP=false  /charts/build-chart.sh
RUN REPO=${REPO}/hardened-kube-proxy CHART_VERSION=${KUBE_PROXY_CHART_VERSION}			 CHART_PACKAGE=${KUBE_PROXY_CHART_PACKAGE_VERSION}              CHART_TAG=${KUBE_PROXY_VERSION}    CHART_FILE=/charts/rke2-kube-proxy.yaml     CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN REPO=${REPO}/hardened-k8s-metrics-server CHART_VERSION=${METRICS_SERVER_CHART_VERSION}                CHART_TAG=${METRICS_SERVER_VERSION}                                                                CHART_FILE=/charts/rke2-metrics-server.yaml CHART_BOOTSTRAP=false  /charts/build-chart.sh
RUN REPO=${REPO}/hardended-multus-cni CHART_VERSION=${MULTUS_CHART_VERSION}                        CHART_TAG=${MULTUS_VERSION}           CHART_TAG_CNI_PLUGIN=${CNI_PLUGINS_VERSION}                  CHART_FILE=/charts/rke2-multus.yaml         CHART_BOOTSTRAP=true   /charts/build-chart.sh
RUN REPO=${REPO}/mirrored-cloud-provider-vsphere-cpi-release-manager CHART_VERSION=${VSPHERE_CPI_CHART_VERSION}                   CHART_TAG=${VSPHERE_CPI_VERSION}                                                                   CHART_FILE=/charts/rancher-vsphere-cpi.yaml CHART_BOOTSTRAP=true   CHART_REPO="https://charts.rancher.io" /charts/build-chart.sh
RUN REPO=${REPO}/mirrored-cloud-provider-vsphere-csi-release-driver CHART_VERSION=${VSPHERE_CSI_CHART_VERSION}                   CHART_TAG=${VSPHERE_CSI_VERSION}                                                                   CHART_FILE=/charts/rancher-vsphere-csi.yaml CHART_BOOTSTRAP=true   CHART_REPO="https://charts.rancher.io" /charts/build-chart.sh
RUN rm -vf /charts/*.sh /charts/*.md /charts/*.yaml-extra

# rke-runtime image
# This image includes any host level programs that we might need. All binaries
# must be placed in bin/ of the file image and subdirectories of bin/ will be flattened during installation.
# This means bin/foo/bar will become bin/bar when rke2 installs this to the host
FROM rancher/k3s:${K3S_VERSION} AS k3s
FROM ${REPO}/hardened-kubernetes:${KUBERNETES_IMAGE_TAG} AS kubernetes
FROM ${REPO}/hardened-containerd:${CONTAINERD_VERSION} AS containerd
FROM ${REPO}/hardened-crictl:${CRICTL_VERSION} AS crictl
FROM ${REPO}/hardened-runc:${RUNC_VERSION} AS runc

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
ENV ETCD_UNSUPPORTED_ARCH=arm64
COPY --from=runtime-collect / /

FROM ubuntu:18.04 AS test
ARG TARGETARCH
ENV ETCD_UNSUPPORTED_ARCH=arm64
VOLUME /var/lib/rancher/rke2
VOLUME /var/lib/kubelet
VOLUME /var/lib/cni
VOLUME /var/log
COPY bin/rke2 /bin/
# use built air-gap images
COPY build/images/rke2-images.linux-amd64.tar.zst /var/lib/rancher/rke2/agent/images/
COPY build/images.txt /images.txt

# use rke2 bundled binaries
ENV PATH=/var/lib/rancher/rke2/bin:$PATH
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
