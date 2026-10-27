# DataGalaxy On-Premises Prerequisites

This repository contains the scripts that verify a Kubernetes cluster intended to host DataGalaxy on premises.

| Check | Script |
|-------|--------|
| Technical account permissions | [scripts/1.verify-permissions.bash](scripts/1.verify-permissions.bash) |
| Dynamic provisioning of persistent volumes | [scripts/2.verify-storage.bash](scripts/2.verify-storage.bash) |
| Exposure through the ingress controller | [scripts/3.verify-ingress.bash](scripts/3.verify-ingress.bash) |

## Prerequisites

The machine running the scripts needs:

- `bash`, `kubectl` and `curl`
- access to the cluster with the technical account planned for the installation (current `kubectl` context)
- network access to the ingress controller, from outside the cluster

This machine must not be a node of the cluster. The ingress test checks access from outside.

On the cluster side:

- the namespace dedicated to DataGalaxy exists
- the `nginxinc/nginx-unprivileged` image is reachable, or imported into the cluster's image registry
- one of the two domain names planned for DataGalaxy points to the ingress controller

## Running the checks

Clone the repository, then run the scripts in order from its root.
In the examples, `datagalaxy` is the namespace and `datagalaxy.client.com` the domain name.

The scripts are configured through environment variables.
Start by setting the namespace dedicated to DataGalaxy and one of its domain names:

```bash
export DG_NAMESPACE=datagalaxy
export DG_DOMAIN=datagalaxy.client.com
```

The `-h` option prints the help of each script.

### 1. Technical account

```bash
./scripts/1.verify-permissions.bash
```

The script checks the account can create every resource type DataGalaxy needs, in the namespace and at cluster level.

### 2. Storage

```bash
./scripts/2.verify-storage.bash
DG_STORAGE_SIZE=2Gi ./scripts/2.verify-storage.bash
```

The test must be run with two different sizes. On each run, the script:

1. checks no volume is prepared in advance for the test PVC
2. creates the `datagalaxy-test` PVC and a POD that uses it
3. waits for the PVC to be `Bound`, then checks the size of the created volume
4. checks the POD can write on the volume
5. deletes the PVC and checks the volume is removed

| Variable | Purpose | Default |
|----------|---------|---------|
| `DG_NAMESPACE` | Namespace dedicated to DataGalaxy | required |
| `DG_STORAGE_SIZE` | Volume size to test | `1Gi` |
| `DG_STORAGE_CLASS` | Storage class | cluster default class |
| `DG_IMAGE` | Test POD image | `nginxinc/nginx-unprivileged` |
| `DG_TIMEOUT` | Maximum wait per step, in seconds | `120` |

### 3. Ingress controller

```bash
./scripts/3.verify-ingress.bash
```

The script lists the ingress classes, the controller PODs and the services exposed outside the cluster.
The operator relies on them to describe how the controller is connected to the outside network.
The script then deploys a test application and queries `http://<domain>/datagalaxy-ingress-test/index.html` and its HTTPS counterpart.
If HTTP does not succeed, the script waits about one minute before moving on to HTTPS.

| Variable | Purpose | Default |
|----------|---------|---------|
| `DG_NAMESPACE` | Namespace dedicated to DataGalaxy | required |
| `DG_DOMAIN` | Domain name planned for DataGalaxy | required |
| `DG_IMAGE` | Web server image | `nginxinc/nginx-unprivileged` |
| `DG_INGRESS_CLASS` | Ingress class | cluster default class |
| `DG_INGRESS_IP` | Controller IP address, when DNS is not set up yet | DNS resolution |
| `DG_TIMEOUT` | Maximum wait for the deployment, in seconds | `120` |
| `DG_KEEP` | `true` to keep the test resources at the end | deleted |

### Image in an internal registry

If the cluster cannot reach Docker Hub, import the image into the internal registry and set its full name before running scripts 2 and 3:

```bash
export DG_IMAGE=my-registry/nginxinc/nginx-unprivileged
```

### Message language

The scripts print their messages in French or English.
The language follows the system locale: French if `LANG` (or `LC_ALL`, `LC_MESSAGES`) starts with `fr`, English otherwise.
Messages are stored in [scripts/i18n](scripts/i18n), one properties file per language.
The `DG_LANG` variable forces the language:

```bash
export DG_LANG=en
```

## Reading the results

Each check prints a verdict:

- `[OK]`: the check passed
- `[WARN]`: point of attention, not blocking. The operator must justify it (e.g. volume kept after the PVC deletion, HTTP traffic forbidden).
- `[FAIL]`: the prerequisite is not met. A new verification must be scheduled.
- `[INFO]`: context, used to support the discussion

Each script ends with a summary.
The exit code is `0` without failure and `1` on failure.
It is `2` when the script cannot run: missing required variable, unreachable cluster or missing namespace.

Test resources are deleted at the end of each script, including on interruption.
With `DG_KEEP=true`, script 3 keeps them and prints the command to delete them.
If a persistent volume is kept because of its reclaim policy, the script prints the command to delete it.

## Manual verification

The manifests used by the scripts are in [k8s_manifests](k8s_manifests).
They can also be applied manually with `kubectl`.
For the ingress test, first replace `datagalaxy.int.domaine.com` with the real domain name.

## Contributing

This project welcomes contributions and suggestions.\
Please have a look at our [Guidelines](CONTRIBUTING.md) for contributing.

Scripts are checked by [ShellCheck](https://www.shellcheck.net) before each commit, through [pre-commit](https://pre-commit.com).
The hook uses the ShellCheck Docker image: Docker must be available on the machine.

To enable the hook:

```bash
pip install pre-commit
pre-commit install
```

Continuous integration runs ShellCheck again and validates the Kubernetes manifests with [kubeconform](https://github.com/yannh/kubeconform).
