#!/usr/bin/env bash

set -eux -o pipefail

: "${KUBERNETES_VERSION:=v0.0.0-0}"
: "${CHART_FILE?required}"
: "${CHART_NAME:="$(basename "${CHART_FILE%%.yaml}")"}"
: "${CHART_PACKAGE:="${CHART_NAME%%-crd}"}"
: "${TAR_OPTS:=--owner=0 --group=0 --mode=gou-s+r --numeric-owner --no-acls --no-selinux --no-xattrs}"
: "${CHART_URL:="${CHART_REPO:="https://rke2-charts.rancher.io"}/assets/${CHART_PACKAGE}/${CHART_NAME}-${CHART_VERSION:="v0.0.0"}.tgz"}"
: "${CHART_TMP:=$(mktemp --suffix .tar.gz)}"
: "${YAML_TMP:=$(mktemp --suffix .yaml)}"

cleanup() {
  exit_code=$?
  trap - EXIT INT
  rm -rf ${CHART_TMP} ${CHART_TMP/tar.gz/tar} ${YAML_TMP}
  exit ${exit_code}
}
trap cleanup EXIT INT

curl -fsSL "${CHART_URL}" -o "${CHART_TMP}"
gunzip ${CHART_TMP}

# Extract out Chart.yaml, inject a version requirement and bundle-id annotation, and delete/replace the one in the original tarball
tar -xf ${CHART_TMP/.gz/}
tar -xOf ${CHART_TMP/.gz/} ${CHART_NAME}/Chart.yaml > ${YAML_TMP}
yq -i e ".kubeVersion = \">= ${KUBERNETES_VERSION}\" | .annotations.\"fleet.cattle.io/bundle-id\" = \"rke2\"" ${YAML_TMP}
tar --delete -b 8192 -f ${CHART_TMP/.gz/} ${CHART_NAME}/Chart.yaml
tar --transform="s|.*|${CHART_NAME}/Chart.yaml|" ${TAR_OPTS} -vrf ${CHART_TMP/.gz/} ${YAML_TMP}

pigz -11 ${CHART_TMP/.gz/}

cat <<-EOF > "${CHART_FILE}"
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: "${CHART_NAME}"
  namespace: "${CHART_NAMESPACE:="kube-system"}"
  annotations:
    helm.cattle.io/chart-url: "${CHART_URL}"
spec:
  bootstrap: ${CHART_BOOTSTRAP:=false}
  chartContent: $(base64 -w0 < "${CHART_TMP}")
EOF

# Check if CHART_FILE-extra.yaml is present and append this to the CHART_FILE. This is a temporarly measure to enable testing arm64 images not available on the offical rancher docker repo.
extra_file="/charts/${CHART_NAME}-extra.yaml"
if [ -f "${extra_file}" ]; then
    cat ${extra_file} >> ${CHART_FILE}
fi
