#!/bin/bash
set -x

PROG=rke2
REGISTRY=${REGISTRY:-docker.io}
REPO=${REPO:-rancher}
K3S_PKG=github.com/rancher/k3s
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
KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.21.4}
RKE2_RELEASE=${RKE2_RELEASE:-rke2r3}
RKE2_MULTIARCH_RELEASE=${RKE2_MULTIARCH_RELEASE:-multiarchAlpha1}
VERSION=${VERSION:-$KUBERNETES_VERSION-$RKE2_MULTIARCH_RELEASE+$RKE2_RELEASE}
REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .dirty; fi)
PLATFORM=${GOOS}-${GOARCH}
RELEASE=${PROG}.${PLATFORM}

K3S_VERSION=${K3S_VERSION:-v1.21.4-k3s1}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-"v1.5.5-k3s1"}
CRICTL_VERSION=${CRICTL_VERSION:-v1.21.0}
RUNC_VERSION=${RUNC_VERSION:-v1.0.2}
KUBERNETES_IMAGE_TAG=${KUBERNETES_IMAGE_TAG:-$KUBERNETES_VERSION-$RKE2_RELEASE}
COREDNS_VERSION=${COREDNS_VERSION:-v1.8.4}
ETCD_VERSION=${ETCD_VERSION:-v3.4.13-k3s1}
METRICS_SERVER_VERSION=${METRICS_SERVER_VERSION:-v0.5.0}
PAUSE_VERSION=${PAUSE_VERSION:-3.5}
KLIPPER_HELM_VERSION=${KLIPPER_HELM_VERSION:-v0.6.4}
JETTECH_VERSION=${JETTECH_VERSION:-v1.5.2}
NGINX_INGRESS_VERSION=${NGINX_INGRESS_VERSION:-1.0.0-multiarch}
NGINX_INGRESS_DEFAULT_BACKEND_VERSION=${NGINX_INGRESS_DEFAULT_BACKEND_VERSION:-1.5-rancher1}
KUBE_PROXY_VERSION=${KUBE_PROXY_VERSION:-v1.21.4}
CCM_VERSION=${CCM_VERSION:-v0.0.1}
CALICO_VERSION=${CALICO_VERSION:-v3.20.0}
CALICO_OPERATOR_VERSION=${CALICO_OPERATOR_VERSION:-v1.22}
CALICO_CRD_VERSION=${CALICO_CRD_VERSION:-v1.17.6}
FLANNEL_VERSION=${FLANNEL_VERSION:-v0.14.0}
CILIUM_VERSION=${CILIUM_VERSION:-v1.10.4}
CILIUM_STARTUP_SCRIPT_VERSION=${CILIUM_STARTUP_SCRIPT_VERSION:-2de58e53a7060593c91d0655b337a57f06bf5d66}
MULTUS_VERSION=${MULTUS_VERSION:-v3.7.2}
CNI_PLUGINS_VERSION=${CNI_PLUGINS_VERSION:-v1.0.0}
SRIOV_VERSION=${SRIOV_VERSION:-v1.0.0}
SRIOV_DEVICE_PLUGIN_VERSION=${SRIOV_DEVICE_PLUGIN_VERSION:-v3.3.2}
SRIOV_CNI_VERSION=${SRIOV_CNI_VERSION:-v2.6.1}
SRIOV_RESOURCES_INJECTOR_VERSION=${SRIOV_RESOURCES_INJECTOR_VERSION:-v1.2}
VSPHERE_CPI_VERSION=${VSPHERE_CPI_VERSION:-v1.2.1}
VSPHERE_CSI_VERSION=${VSPHERE_CSI_VERSION:-v2.1.0}
K8SCSI_CSI_ATTACHER_VERSION=${K8SCSI_CSI_ATTACHER_VERSION:-"v3.0.0"}
K8SCSI_CSI_NODE_DRIVER_VERSION=${K8SCSI_CSI_NODE_DRIVER_VERSION:-"v2.0.1"}
K8SCSI_CSI_PROVISIONER_VERSION=${K8SCSI_CSI_PROVISIONER_VERSION:-"v2.0.0"}
K8SCSI_CSI_RESIZER_VERSION=${K8SCSI_CSI_RESIZER_VERSION:-"v1.0.0"}
K8SCSI_CSI_LIVENESSPROBE_VERSION=${K8SCSI_CSI_LIVENESSPROBE_VERSION:-"v2.1.0"}

CILIUM_CHART_VERSION=${CILIUM_CHART_VERSION:-"1.9.808"}
CANAL_CHART_VERSION=${CANAL_CHART_VERSION:-"v3.19.1-build2021061107"}
CALICO_CHART_VERSION=${CALICO_CHART_VERSION:-"v3.19.2-203"}
CALICO_CRD_CHART_VERSION=${CALICO_CRD_CHART_VERSION:-"v1.0.103"}
COREDNS_CHART_VERSION=${COREDNS_CHART_VERSION:-"1.16.201-build2021072308"}
NGINX_INGRESS_CHART_VERSION=${NGINX_INGRESS_CHART_VERSION:-"3.34.003"}
KUBE_PROXY_CHART_VERSION=${KUBEPROXY_CHART_VERSION:-"v1.21.4-rke2r3-build2021090101"}
KUBE_PROXY_CHART_PACKAGE_VERSION=${KUBE_PROXY_CHART_PACKAGE_VERSION:-"rke2-kube-proxy-1.21"}
METRICS_SERVER_CHART_VERSION=${METRICS_SERVER_CHART_VERSION:-"2.11.100-build2021022302"}
MULTUS_CHART_VERSION=${MULTUS_CHART_VERSION:-"v3.7.1-build2021041604"}
VSPHERE_CPI_CHART_VERSION=${VSPHERE_CPI_CHART_VERSION:-"1.0.000"}
VSPHERE_CSI_CHART_VERSION=${VSPHERE_CSI_CHART_VERSION:-"2.1.000"}

GIT_TAG="${VERSION}"

if [[ "${VERSION}" =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?([-+].*)?$ ]]; then
    VERSION_MAJOR=${BASH_REMATCH[1]}
    VERSION_MINOR=${BASH_REMATCH[2]}
fi

DOCKERIZED_VERSION="${VERSION/+/-}" # this mimics what kubernetes builds do
