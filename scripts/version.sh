#!/bin/bash
set -x

PROG=rke2
REGISTRY=docker.io
REPO=${REPO:-rancher}
K3S_PKG=github.com/rancher/k3s
RKE2_PKG=github.com/rancher/rke2
GO=${GO-go}
GOARCH=${GOARCH:-$("${GO}" env GOARCH)}
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

GIT_TAG=$DRONE_TAG
TREE_STATE=clean
COMMIT=$DRONE_COMMIT
REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .dirty; fi)
PLATFORM=${GOOS}-${GOARCH}
RELEASE=${PROG}.${PLATFORM}
if [[ ! -z "$IMAGE_BUILD_VERSION" ]]; then IMAGE_BUILD_VERSION=-${IMAGE_BUILD_VERSION}; fi
if [[ ! $GOARCH == amd64 ]]; ARCH_EXTRA=-${GOARCH}; fi

# hardcode versions unless set specifically
KUBERNETES_VERSION=${KUBERNETES_VERSION:-v1.21.0}
KUBE_PROXY_VERSION=${KUBE_PROXY_VERSION:-${KUBERNETES_VERSION}}
ETCD_VERSION=${ETCD_VERSION:-v3.4.13-k3s1}
PAUSE_VERSION=${PAUSE_VERSION:-3.2}
RUNC_VERSION=${RUNC_VERSION:-v1.0.0-rc93}
CRICTL_VERSION=${CRICTL_VERSION:-v1.21.0}
CONTAINERD_VERSION=${CONTAINERD_VERSION:-v1.4.4-k3s1}
PROTOC_VERSION=${PROTOC_VERSION:-3.11.4}
METRICS_SERVER_VERSION=${METRICS_SERVER_VERSION:-v0.4.4}
COREDNS_VERSION=${COREDNS_VERSION:-v1.8.3}
K3S_VERSION=${K3S_VERSION:-$KUBERNETES_VERSION-k3s1}
K3S_ROOT_VERSION=${K3S_ROOT_VERSION:-v0.8.1}
FLANNEL_VERSION=${FLANNEL_VERSION:-v0.13.0-rancher1}
CANAL_VERSION=${CANAL_VERSION:-v3.15.5}
CALICO_VERSION=${CALICO_VERSION:-v3.18.1}
CALICO_OPERATOR_VERSION=${CALICO_OPERATOR_VERSION:-v1.15.1}
CALICO_BIRD_VERSION=${CALICO_BIRD_VERSION:-v0.3.3-169-g0b0c2c14}
CALICO_BPFTOOL_VERSION=${CALICO_BPFTOOL_VERSION:-v5.3}
CALICO_CRD_VERSION=${CALICO_CRD_VERSION:-v1.0.002}
CNI_PLUGINS_VERSION=${CNI_PLUGINS_VERSION:-v0.9.1}
HELM_VERSION=${HELM_VERSION:-v0.5.0-build20210505}
NGINX_INGRESS_VERSION=${NGINX_INGRESS_VERSION:-nginx-0.30.0-rancher1}
NGINX_INGRESS_DEFAULT_BACKEND_VERSION=${NGINX_INGRESS_DEFAULT_BACKEND_VERSION:-1.5-rancher1}
CILIUM_VERSION=${CILIUM_VERSION:-v1.10.0-rc1}
CILIUM_STARTUP_SCRIPT_VERSION=${CILIUM_STARTUP_SCRIPT_VERSION:-62bfbe88c17778aad7bef9fa57ff9e2d4a9ba0d8}
VSPHERE_CPI_VERSION=${VSPHERE_CPI_RELEASE_MANAGER_VERSION:-v1.2.1}
VSPHERE_CSI_VERSION=${VSPHERE_CSI_RELEASE_DRIVER_VERSION:-v2.1.0}
K8SCSI_CSI_ATTACHER_VERSION=${K8SCSI_CSI_ATTACHER_VERSION:-v3.0.0}
K8SCSI_CSI_NODE_DRIVER_REGISTRAR_VERSION=${K8SCSI_CSI_NODE_DRIVER_REGISTRAR_VERSION:-v2.0.1}
K8SCSI_CSI_PROVISIONER_VERSION=${K8SCSI_CSI_PROVISIONER_VERSION:-v2.0.0}
K8SCSI_CSI_RESIZER_VERSION=${K8SCSI_CSI_RESIZER_VERSION:-v1.0.0}
MULTUS_VERSION=${MULTUS_VERSION:-v3.7.1}
CILIUM_CHART_VERSION=${CILIUM_CHART_VERSION:-"1.9.604"}
CANAL_CHART_VERSION=${CANAL_CHART_VERSION:-"v3.13.300-build2021022303"}
CALICO_CHART_VERSION=${CALICO_CHART_VERSION:-"v3.18.1-103"}
CALICO_CRD_CHART_VERSION=${CALICO_CRD_CHART_VERSION:-"v1.0.003"}
COREDNS_CHART_VERSION=${COREDNS_CHART_VERSION:-"1.10.101-build2021022303"}
NGINX_INGRESS_CHART_VERSION=${NGINX_INGRESS_CHART_VERSION:-"1.36.301"}
KUBE_PROXY_CHART_VERSION=${KUBEPROXY_CHART_VERSION:-"v1.21.0-build2021041302"}
METRICS_SERVER_CHART_VERSION=${METRICS_SERVER_CHART_VERSION:-"2.11.100-build2021022300"}
MULTUS_CHART_VERSION=${MULTUS_CHART_VERSION:-"v3.7.1-build2021041601"}
VSPHERE_CPI_CHART_VERSION=${VSPHERE_CPI_CHART_VERSION:-"1.0.000"}
VSPHERE_CSI_CHART_VERSION=${VSPHERE_CSI_CHART_VERSION:-"2.1.000"}

if [ -d .git ]; then
    if [ -z "$GIT_TAG" ]; then
        GIT_TAG=$(git tag -l --contains HEAD | head -n 1)
    fi
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        DIRTY="-dirty"
        TREE_STATE=dirty
    fi

    COMMIT=$(git log -n3 --pretty=format:"%H %ae" | grep -v ' drone@localhost$' | cut -f1 -d\  | head -1)
    if [ -z "${COMMIT}" ]; then
        COMMIT=$(git rev-parse HEAD || true)
    fi
fi

if [[ -n "$GIT_TAG" ]]; then
    VERSION=$GIT_TAG
else
    VERSION="${KUBERNETES_VERSION}-dev+${COMMIT:0:8}$DIRTY"
fi

if [[ "${VERSION}" =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?([-+].*)?$ ]]; then
    VERSION_MAJOR=${BASH_REMATCH[1]}
    VERSION_MINOR=${BASH_REMATCH[2]}
fi

DOCKERIZED_VERSION="${VERSION/+/-}" # this mimics what kubernetes builds do
