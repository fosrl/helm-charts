# Fossorial Kubernetes Helm Charts

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/fosrl?style=flat-square)](https://artifacthub.io/packages/search?org=fosrl)
[![Pangolin Chart Version: 1.1.0](https://img.shields.io/badge/Pangolin%20Chart-1.1.0-informational?style=flat-square)](https://github.com/fosrl/helm-charts/releases)
[![Newt Chart Version: 1.1.1](https://img.shields.io/badge/Newt%20Chart-1.1.1-informational?style=flat-square)](https://github.com/fosrl/helm-charts/releases)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](https://opensource.org/license/mit)
![Release Charts](https://github.com/fosrl/helm-charts/actions/workflows/helm-ci.yml/badge.svg?branch=main)
[![Releases downloads](https://img.shields.io/github/downloads/fosrl/helm-charts/total.svg?style=flat-square)](https://github.com/fosrl/helm-charts/releases)

Welcome to the official repository for **Fossorial Kubernetes Helm Charts**, featuring Helm charts for

- [Pangolin](https://github.com/fosrl/helm-charts/tree/main/charts/pangolin)
- [Newt](https://github.com/fosrl/helm-charts/tree/main/charts/newt)

## Installation & Usage

To use these charts, you need [Helm](https://helm.sh/).  
For setup and advanced documentation, visit the official [Helm documentation](https://helm.sh/docs/).

### Add Fossorial Helm Chart Repository

```console
helm repo add fossorial https://charts.fossorial.io

helm repo update fossorial
```

### Explore Available Charts

You can then run `helm search repo fossorial` to see the charts.

### Install a Chart

Example to install the Pangolin chart:

```console
helm install my-pangolin fossorial/pangolin
```

Example to install the Newt chart:

```console
helm install my-newt fossorial/newt
```

### Uninstall a Chart

Uninstalling a chart can be done with:

```console
helm uninstall my-pangolin
```

For more details, please refer to the individual chart READMEs in the `charts/` directory.

## Contributions

Looking for something to contribute? Take a look at issues marked with [help wanted](https://github.com/fosrl/helm-charts/issues?q=is%3Aissue%20state%3Aopen%20label%3A%22help%20wanted%22).

Please see [CONTRIBUTING](./CONTRIBUTING.md) in the repository for guidelines and best practices.

Please post bug reports and other functional issues in the [Issues](https://github.com/fosrl/helm-charts/issues) section of the repository.

## Licensing

The charts in this repository are licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
