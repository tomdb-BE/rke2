# RKE2 Multiarch
This is an EXPERIMENTAL fork of Rancher's RKE2 adding arm64 support for testing/lab use.

WARNING: Use at own risk. Builds and releases are not supported by Rancher nor author.

Supporting (hardened) images source can be found in their respective repository within this organization.
Same source can be used to build for amd64 as well. Currently, cross compile is not available. A RPI4B is capable of building all packages and images (ensure sufficient storage and swap is available)

Most significant changes compared with master:

- All hardened supporting images (kubernetes, etcd, sriov, calico,..) and mirrored images are available for arm64 except vSphere related mirrored images. Those are skipped during image building on arm64 only.
- Boring assertion is skipped in all supporting hardened images as currently not working for arm64 architecture. When building for amd64, boring assertion is not skipped.
- Hardened images ubi7 base image has been replaced with centos:7 as ubi 7 does not support arm64. Ubi8 does, to be investigated as missing some packages (e.g. conntrack).
- Extended the available versioning variables in scripts/version and main Dockerfile to facilitate building future releases of rke2 and supporting components.

Current state: initial/superficial testing succesful in mixed linux-amd64/linux-arm64 (RPI4B-4GB) three node cluster (k8s - etcd - canal - metrics - kubeproxy - coredns) on RPI4B 4GB RAM.

List of arm64 adapted images and source code (multiarch branch):

[kubernetes]https://github.com/tomdb-be/image-build-kubernetes
[containerd]https://github.com/tomdb-be/image-build-containerd
[runc]https://github.com/tomdb-be/image-build-runc
[crictl]https://github.com/tomdb-be/image-build-crictl
[coredns]https://github.com/tomdb-be/image-build-coredns
[metrics server]https://github.com/tomdb-be/image-build-k8s-metrics-server
[etcd]https://github.com/tomdb-be/image-build-etcd
[rke2-cloud-provider]https://github.com/tomdb-be/image-build-rke2-cloud-provider
[kube-proxy]https://github.com/tomdb-be/image-build-kube-proxy
[calico]https://github.com/tomdb-be/image-build-calico
[flannel]https://github.com/tomdb-be/image-build-flannel
[cni-plugins]https://github.com/tomdb-be/image-build-cni-plugins
[multus]https://github.com/tomdb-be/image-build-multus
[sriov-ib-cni]https://github.com/tomdb-be/image-build-ib-sriov-cni
[sriov-cni]https://github.com/tomdb-be/image-build-sriov-cni
[sriov-network-resource-injector]https://github.com/tomdb-be/image-build-sriov-network-resources-injector
[sriov-network-device-plugin]https://github.com/tomdb-be/image-build-sriov-network-device-plugin
[sriov-operator]https://github.com/tomdb-be/image-build-sriov-operator
[ingress-nginx]https://github.com/tomdb-be/nginx-ingress
[klipper-helm]https://github.com/tomdb-be/klipper-helm
[build-base]https://github.com/tomdb-be/image-build-base


# RKE2
![RKE2](docs/assets/logo-horizontal-rke.svg)

RKE2, also known as RKE Government, is Rancher's next-generation Kubernetes distribution.

It is a fully [conformant Kubernetes distribution](https://landscape.cncf.io/selected=rke-government) that focuses on security and compliance within the U.S. Federal Government sector.

To meet these goals, RKE2 does the following:

- Provides [defaults and configuration options](security/hardening_guide.md) that allow clusters to pass the [CIS Kubernetes Benchmark](security/cis_self_assessment.md) with minimal operator intervention
- Enables [FIPS 140-2 compliance](https://docs.rke2.io/security/fips_support/)
- Supports SELinux policy and [Multi-Category Security (MCS)](https://selinuxproject.org/page/NB_MLS) label enforcement
- Regularly scans components for CVEs using [trivy](https://github.com/aquasecurity/trivy) in our build pipeline

For more information and detailed installation and operation instructions, [please visit our docs](https://docs.rke2.io/).

## Quick Start
Here's the ***extremely*** quick start:
```sh
curl -sfL https://get.rke2.io | sh -
systemctl enable rke2-server.service
systemctl start rke2-server.service
# Wait a bit
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=$PATH:/var/lib/rancher/rke2/bin
kubectl get nodes
```
For a bit more, [check out our full quick start guide](https://docs.rke2.io/install/quickstart/).

## Installation

A full breakdown of installation methods and information can be found [here](docs/install/methods.md).

## Configuration File

The primary way to configure RKE2 is through its [config file](https://docs.rke2.io/install/install_options/install_options/#configuration-file). Command line arguments and environment variables are also available, but RKE2 is installed as a systemd service and thus these are not as easy to leverage.

By default, RKE2 will launch with the values present in the YAML file located at `/etc/rancher/rke2/config.yaml`.

An example of a basic `server` config file is below:

```yaml
# /etc/rancher/rke2/config.yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "foo.local"
node-label:
  - "foo=bar"
  - "something=amazing"
```

In general, cli arguments map to their respective yaml key, with repeatable cli args being represented as yaml lists. So, an identical configuration using solely cli arguments is shown below to demonstrate this:

```bash
rke2 server \
  --write-kubeconfig-mode "0644"    \
  --tls-san "foo.local"             \
  --node-label "foo=bar"            \
  --node-label "something=amazing"
```

It is also possible to use both a configuration file and cli arguments.  In these situations, values will be loaded from both sources, but cli arguments will take precedence.  For repeatable arguments such as `--node-label`, the cli arguments will overwrite all values in the list.

Finally, the location of the config file can be changed either through the cli argument `--config FILE, -c FILE`, or the environment variable `$RKE2_CONFIG_FILE`.

## FAQ

- [How is this different from RKE1 or K3s?](https://docs.rke2.io/#how-is-this-different-from-rke-or-k3s)
- [Why two names?](https://docs.rke2.io/#why-two-names)

## Security

Security issues in RKE2 can be reported by sending an email to [security@rancher.com](mailto:security@rancher.com). Please do not open security issues here.
