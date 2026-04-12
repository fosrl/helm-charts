<!-- markdownlint-disable MD033 -->
# Newt Helm Chart - Quickstart

This guide shows supported ways to install the Newt Helm chart:

- Legacy credential installs (existing Secret or inline ID/secret)
- Newt 1.11+ provisioning installs (provisioning key + writable config persistence)

## Prerequisites

- Kubernetes Cluster: >= 1.30.14
- `kubectl` configured for your cluster
- Helm CLI: v3
- Chart version: 1.3.0 (or newer)

Namespace in examples below: `newt-ns`

## Option A (preferred): Use an existing Secret

1) Store your credentials in a file (e.g. `newt-cred.env`) and avoid CLI input:

    Example content for `newt-cred.env`:

    ```env
    PANGOLIN_ENDPOINT=https://pangolin.yourdomain.com
    NEWT_ID=yourNewtID
    NEWT_SECRET=yourSecretPassword
    ```

    Do not commit this file to git. It should only exist locally/temporarily. Optionally protect it with `chmod 600 newt-cred.env`.

2) Create the Secret directly from the file:

    ```bash
    kubectl create secret generic newt-cred -n newt-ns --from-env-file=newt-cred.env
    ```

3) Create a values file that fits your requirements. For this Test we create a minimal values file called `myvalues.yaml`:

    ```yaml
    newtInstances:
      - name: main
        enabled: true
        auth:
          existingSecretName: newt-cred
    ```

4) Install the chart:

    The command below installs the chart with your chosen release name (`newt`), namespace (`newt-ns`), and values file (`myvalues.yaml`). You can change these to fit your environment. (helm install <release-name> <chart> -n <namespace> -f <values-file>)

    ```bash
    helm repo add fossorial https://charts.fossorial.io
    helm repo update fossorial

    helm install newt fossorial/newt -n newt-ns --create-namespace -f myvalues.yaml
    ```

    Alternative instead of using a values file you can set the values directly in the command line:

    ```bash
    helm install newt fossorial/newt \
      -n newt-ns --create-namespace \
      --set newtInstances[0].name=main \
      --set newtInstances[0].enabled=true \
      --set newtInstances[0].auth.existingSecretName=newt-cred
    ```

## Option B: Inline credentials via Helm values

If you prefer to provide credentials inline (not recommended), install with:

```bash
export NEWT_SECRET='<your-secret-here>'   # Set securely
helm install newt fossorial/newt -n newt-ns --create-namespace \
  --set newtInstances[0].name=main \
  --set newtInstances[0].enabled=true \
  --set newtInstances[0].pangolinEndpoint=https://pangolin.yourdomain.com \
  --set newtInstances[0].id=XXXX \
  --set-string newtInstances[0].secret="$NEWT_SECRET"
```

## Option C: Provisioning (Newt 1.11+)

Provisioning uses a provisioning key and requires a writable `CONFIG_FILE` target. The chart provides this via `newtInstances[x].configPersistence`.

Example `myvalues.yaml` (ephemeral persistence via emptyDir):

```yaml
newtInstances:
  - name: main
    enabled: true
    pangolinEndpoint: https://pangolin.yourdomain.com

    provisioningKey: "YOUR_PROVISIONING_KEY"
    newtName: "my-site"

    configPersistence:
      enabled: true
      type: emptyDir
      mountPath: /var/lib/newt
      fileName: config.json
```

Install:

```bash
helm install newt fossorial/newt -n newt-ns --create-namespace -f myvalues.yaml
```

## Notes

- Credentials required: When an instance is enabled, you must supply credentials via one of: `auth.existingSecretName`, inline `id`/`secret`, or `provisioningKey`.
- Test Job: Helm test Jobs are gated behind `global.tests.enabled` (default: false) and will only render and run when enabled.
- NetworkPolicy: NetworkPolicies are controlled by `global.networkPolicy.enabled` with per-instance overrides under `newtInstances[x].networkPolicy`.
- Security: Never commit secrets into version control. Prefer existing Secret, sealed-secrets, or other secret managers.

## Troubleshooting

- Dry-run template:

```bash
helm template newt fossorial/newt --namespace newt-ns -f myvalues.yaml
```

- Uninstall:

```bash
helm uninstall newt -n newt-ns
```
