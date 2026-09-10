# Kubernetes Version Matrix

This file tracks chart versions, default app versions, and related defaults for Kubernetes documentation pages.

## Newt (Site)

| Item | Value |
| --- | --- |
| Chart version | `1.6.0` |
| App version | `1.16.0` |
| Kubernetes version | `>=1.30.14-0` |
| Default image tag | `1.16.0` |

Sources:

- [Newt chart source](https://github.com/fosrl/helm-charts/tree/main/charts/newt)
- [Newt on Artifact Hub](https://artifacthub.io/packages/helm/fosrl/newt)

## Pangolin

| Item | Value |
| --- | --- |
| Chart version | `0.1.0-alpha.2` |
| App version | `1.22.2` |
| Kubernetes version | `>=1.30.14-0` |
| Pangolin default image tag | `1.22.2` |
| Pangolin PostgreSQL image tag | `postgresql-1.22.2` |
| pangolin-kube-controller tag | `0.1.0-alpha.1` |
| Gerbil tag | `1.5.1` |
| Traefik tag | `v3.6.15` |

Sources:

- [Pangolin chart source](https://github.com/fosrl/helm-charts/tree/main/charts/pangolin)
- [Pangolin on Artifact Hub](https://artifacthub.io/packages/helm/fosrl/pangolin)

## Component compatibility

Pangolin's components are released independently and carry hard minimum versions.
These are upstream requirements, not chart policy.

| Pangolin | Newt | Gerbil | Badger | Notes |
| --- | --- | --- | --- | --- |
| `>= 1.19.0` | `>= 1.13.0` | — | `>= v1.4.1` | Browser-based RDP/SSH/VNC and the SSH resource type. |
| `>= 1.22.0` | `>= 1.13.0` | `>= 1.5.0` | `>= v1.6.0` | AI gateway. Gerbil `1.5.0` is required only for **private** AI gateway resources. |

Badger `v1.6.0`, `v1.6.1` and `v1.7.0` are functionally identical; the later tags were
re-released to work around a Traefik plugin registry outage.

> [!IMPORTANT]
> Badger is a Traefik plugin, so it is loaded by your Traefik installation rather than by
> this chart. Upgrading Pangolin does not upgrade Badger — check its version in your
> Traefik static configuration when moving to Pangolin `1.22`.

Private AI gateway resources additionally require Pangolin clients released after
2026-08-19.
