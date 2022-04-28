#!/bin/bash
set -x

PROG=rke2
REGISTRY=${REGISTRY:-docker.io}
REPO=${REPO:-rancher}
K3S_PKG=github.com/k3s-io/k3s
RKE2_PKG=github.com/rancher/rke2
GO=${GO-go}
GOARCH=${GOARCH:-$("${GO}" env GOARCH)}
ARCH=${GOARCH}
GOOS=${GOOS:-$("${GO}" env GOOS)}
if [ -z "$GOOS" ]; then
    if [ "${OS}" == "Windows_NT" ]; then
      GOOS="windows"
    else
      UNAME_S=$(shell uname -s)
                  if [ "${UNAME_S}" == "Linux" ]; then
                            GOOS="linux"
                  elif [ "${UNAME_S}" == "Darwin" ]; then
                                  GOOS="darwin"
                  elif [ "${UNAME_S}" == "FreeBSD" ]; then
                                  GOOS="freebsd"
                  fi
    fi
fi
GOOS=linux
UNAME_S=Linux
TREE_STATE=clean
COMMIT=$DRONE_COMMIT
if [ -z "${IMAGE_BUILD_VERSION}" ]; then IMAGE_BUILD_VERSION=multiarch-build$(date +%Y%m%d); fi
BASE_VERSION=${BASE_VERSION:-v1.18.1b7-multiarch}
RKE2_RELEASE=${RKE2_RELEASE:-rke2r1}
RKE2_MULTIARCH_RELEASE=${RKE2_MULTIARCH_RELEASE:-multiarch-alpha1}
VERSION=${VERSION:-$KUBERNETES_VERSION-$RKE2_MULTIARCH_RELEASE+$RKE2_RELEASE}
REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .dirty; fi)
PLATFORM=${GOOS}-${GOARCH}
RELEASE=${PROG}.${PLATFORM}

# hardcode versions unless set specifically
KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.23.6}
KUBERNETES_IMAGE_TAG=${KUBERNETES_IMAGE_TAG:-$KUBERNETES_VERSION-$RKE2_RELEASE}
ETCD_VERSION=${ETCD_VERSION:-v3.5.4-k3s1}
PAUSE_VERSION=${PAUSE_VERSION:-3.6}
CCM_VERSION=${CCM_VERSION:-v0.0.3}

if [ -d .git ]; then
    if [ -z "$GIT_TAG" ]; then
        GIT_TAG=$(git tag -l --contains HEAD | head -n 1)
    fi
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        DIRTY="-dirty"
        TREE_STATE=dirty
    fi
fi

CONTAINERD_VERSION=${CONTAINERD_VERSION:-v1.6.2-k3s2}
CRICTL_VERSION=${CRICTL_VERSION:-v1.23.0}
RUNC_VERSION=${RUNC_VERSION:-v1.1.1}

COREDNS_VERSION=${COREDNS_VERSION:-v1.9.1}
CLUSTER_AUTOSCALER_VERSION=${CLUSTER_AUTOSCALER_VERSION:-v1.8.5}
METRICS_SERVER_VERSION=${METRICS_SERVER_VERSION:-v0.6.1}
KLIPPER_HELM_VERSION=${KLIPPER_HELM_VERSION:-v0.7.2-build20220413}
NGINX_INGRESS_VERSION=${NGINX_INGRESS_VERSION:-nginx-1.2.0-multiarch-hardened6-amd64}
NGINX_INGRESS_DEFAULT_BACKEND_VERSION=${NGINX_INGRESS_DEFAULT_BACKEND_VERSION:-1.5-rancher1}
HARDENED_CALICO_VERSION=${HARDENEDCALICO_VERSION:-v3.22.2}
CALICO_VERSION=${CALICO_VERSION:-v3.22.2}
CALICO_OPERATOR_VERSION=${CALICO_OPERATOR_VERSION:-v1.25.0}
CALICO_CRD_VERSION=${CALICO_CRD_VERSION:-v1.0.202}
FLANNEL_VERSION=${FLANNEL_VERSION:-v0.17.0}
CILIUM_VERSION=${CILIUM_VERSION:-v1.11.4}
CILIUM_STARTUP_SCRIPT_VERSION=${CILIUM_STARTUP_SCRIPT_VERSION:-62bfbe88c17778aad7bef9fa57ff9e2d4a9ba0d8}
MULTUS_VERSION=${MULTUS_VERSION:-v3.8}
CNI_PLUGINS_VERSION=${CNI_PLUGINS_VERSION:-v1.0.1}
SRIOV_VERSION=${SRIOV_VERSION:-v1.0.0-multiarch-build20210908}
SRIOV_DEVICE_PLUGIN_VERSION=${SRIOV_DEVICE_PLUGIN_VERSION:-v3.3.2-multiarch-build20210908}
SRIOV_CNI_VERSION=${SRIOV_CNI_VERSION:-v2.6.1-multiarch-build20210908}
SRIOV_RESOURCES_INJECTOR_VERSION=${SRIOV_RESOURCES_INJECTOR_VERSION:-v1.2-multiarch-build20210908}
VSPHERE_CPI_VERSION=${VSPHERE_CPI_VERSION:-v1.21.0}
VSPHERE_CSI_VERSION=${VSPHERE_CSI_VERSION:-v2.3.0}
K8SCSI_CSI_ATTACHER_VERSION=${K8SCSI_CSI_ATTACHER_VERSION:-v3.2.0}
K8SCSI_CSI_NODE_DRIVER_VERSION=${K8SCSI_CSI_NODE_DRIVER_VERSION:-v2.1.0}
K8SCSI_CSI_PROVISIONER_VERSION=${K8SCSI_CSI_PROVISIONER_VERSION:-v2.2.0}
K8SCSI_CSI_RESIZER_VERSION=${K8SCSI_CSI_RESIZER_VERSION:-v1.1.0}
K8SCSI_CSI_LIVENESSPROBE_VERSION=${K8SCSI_CSI_LIVENESSPROBE_VERSION:-v2.2.0}
DNS_NODE_CACHE_VERSION=${DNS_NODE_CACHE_VERSION:-1.22.1}
CERTGEN_VERSION=${CERTGEN_VERSION:-v1.0}
HARVESTER_VERSION=${HARVESTER_VERSION:-v0.1.3-multiarch}
LONGHORN_REGISTRAR_VERSION=${LONGHORN_REGISTRAR_VERSION:-v2.3.0}
LONGHORN_RESIZER_VERSION=${LONGHORN_PROVISIONER_VERSION:-v1.2.0}
LONGHORN_PROVISIONER_VERSION=${LONGHORN_PROVISIONER_VERSION:-v2.1.2}
LONGHORN_ATTACHER_VERSION=${LONGHORN_ATTACHER_VERSION:-v3.2.1}

CILIUM_CHART_VERSION=${CILIUM_CHART_VERSION:-"1.11.203"}
CANAL_CHART_VERSION=${CANAL_CHART_VERSION:-"4.1.001"}
CALICO_CHART_VERSION=${CALICO_CHART_VERSION:-"v3.22.101"}
CALICO_CRD_CHART_VERSION=${CALICO_CRD_CHART_VERSION:-"v1.0.202"}
COREDNS_CHART_VERSION=${COREDNS_CHART_VERSION:-"1.17.000"}
NGINX_INGRESS_CHART_VERSION=${NGINX_INGRESS_CHART_VERSION:-"4.1.001"}
METRICS_SERVER_CHART_VERSION=${METRICS_SERVER_CHART_VERSION:-"2.11.100-build2021111904"}
MULTUS_CHART_VERSION=${MULTUS_CHART_VERSION:-"3.7.1-build2021111906"}
VSPHERE_CPI_CHART_VERSION=${VSPHERE_CPI_CHART_VERSION:-"1.2.101"}
VSPHERE_CSI_CHART_VERSION=${VSPHERE_CSI_CHART_VERSION:-"2.5.1-rancher101"}
HARVESTER_CLOUD_PROVIDER_CHART_VERSION=${HARVESTER_CLOUD_PROVIDER_CHART_VERSION:-"0.1.1100"}
HARVESTER_CSI_DRIVER_CHART_VERSION=${HARVESTER_CSI_DRIVER_CHART_VERSION:-"0.1.1100"}


GIT_TAG="${VERSION}"

if [[ "${VERSION}" =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?([-+].*)?$ ]]; then
    VERSION_MAJOR=${BASH_REMATCH[1]}
    VERSION_MINOR=${BASH_REMATCH[2]}
fi

DOCKERIZED_VERSION="${VERSION/+/-}" # this mimics what kubernetes builds do
