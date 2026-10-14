# Installing Fibrik

One Helm chart (`deploy/helm/fibrik`) runs everywhere. Pick the host, then
the values profile. Nothing in the chart or the code changes between hosts
(`initial-stack.md` §0).

| Host | Kubernetes | Command | Profile |
|---|---|---|---|
| GitHub Codespace | kind or k3d (Docker-in-Docker) | `make k3d-up` | `ci` or `poc` |
| Mac mini (Apple Silicon, arm64) | k3d on Colima | `make k3d-up` | default or `poc` |
| Any Linux VM or server | k3s | `sudo hack/install-k3s.sh` | `free` |
| OCI Always Free (when available) | k3s, via `deploy/tofu/oci` | `tofu apply` | `free` |

All tools (helm, kind, k3d, kubectl, flux, tofu, cosign) are pinned and
downloaded into `./.bin` by `make` on first use, with checksum checks.

## 1. Build or pull the images

CI publishes signed multi-arch images on every merge to `main`:
`ghcr.io/sclinton/fibrik-api` and `ghcr.io/sclinton/fibrik-otelcol`, tagged
with the commit SHA and `latest`. The packages must be public for clusters
to pull them without credentials: GitHub → your profile → Packages → each
package → Package settings → Change visibility → Public.

To verify a signature:

```sh
cosign verify ghcr.io/sclinton/fibrik-api:latest \
  --certificate-identity-regexp 'https://github.com/SClinton/fibrik/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

To build locally instead: `make images` (tag `dev`), then load them into the
cluster with `make k3d-load` or `make kind-load`.

## 2. A single machine: Codespace or Mac mini

```sh
make k3d-up                      # k3s in Docker, Traefik off, UI on localhost:8080
make images k3d-load             # or skip and use the published images (IMAGE_TAG=latest)
make deploy                      # PROFILE=ci by default: small volumes, mock login
make test e2e                    # smoke tests, then a syslog line through to Iceberg
```

On the Mac mini, start Docker first with Colima. The default 2 GB VM is too
small: `colima start --cpu 4 --memory 8`.

Open <http://localhost:8080>. In a Codespace, use the forwarded port 8080.

### Lake on Cloudflare R2 (`poc` profile)

```sh
kubectl create namespace fibrik
kubectl -n fibrik create secret generic fibrik-storage \
  --from-literal=access-key-id="$R2_ACCESS_KEY_ID" \
  --from-literal=secret-access-key="$R2_SECRET_ACCESS_KEY"
make deploy PROFILE=poc \
  EXTRA_ARGS="--set storage.endpoint=https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"
```

The `R2_*` values come from Codespaces secrets; never put them in values files.

## 3. Any Linux host with k3s

```sh
sudo hack/install-k3s.sh                         # k3s, Traefik off, ServiceLB on
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Then either `make deploy PROFILE=free` once, or hand the cluster to Flux
(next section). The `free` profile needs:

- a DNS name pointing at the host, set as `caddy.domain` and
  `global.publicUrl`, with port 443 open;
- a `fibrik-storage` Secret for the S3 bucket, and `storage.endpoint`;
- a `fibrik-dex-github` Secret with `GITHUB_CLIENT_ID` and
  `GITHUB_CLIENT_SECRET` (see section 6).

## 4. GitOps with Flux

```sh
make gitops CLUSTER=local        # or CLUSTER=free
```

This installs Flux and applies `deploy/flux/clusters/<CLUSTER>`, which
points a `HelmRelease` at this repository's chart. Every commit on `main`
redeploys; local edits to the cluster are reverted. Check progress with
`flux get helmreleases -A`.

## 5. OCI Always Free (optional)

`deploy/tofu/oci` creates one Ampere A1 VM (2 OCPU / 12 GB), a 100 GB data
volume mounted where k3s keeps its volumes, an Object Storage bucket and a
network that only opens 443 (and 22 from `admin_cidr`, if set). Variable
validation rejects sizes outside the Always Free limits.

```sh
cd deploy/tofu/oci
tofu init
tofu apply -var region=... -var compartment_ocid=... -var ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
```

The outputs give the public IP (for DNS) and the S3 endpoint (for
`storage.endpoint`). The tenancy needs a customer secret key for the S3 API
(Profile → Customer secret keys), stored as the `fibrik-storage` Secret.

## 6. Sign-in with GitHub (Dex)

1. GitHub → Settings → Developer settings → OAuth Apps → New OAuth App.
   - Homepage URL: your `global.publicUrl`.
   - Authorization callback URL: `<publicUrl>/dex/callback`. In a Codespace
     this is `https://<codespace-name>-8080.app.github.dev/dex/callback`.
2. Store the client ID and secret in your password manager, then:

   ```sh
   kubectl -n fibrik create secret generic fibrik-dex-github \
     --from-literal=GITHUB_CLIENT_ID=... --from-literal=GITHUB_CLIENT_SECRET=...
   make deploy PROFILE=<profile> EXTRA_ARGS="--set dex.envFromSecret=fibrik-dex-github \
     --set global.publicUrl=<publicUrl>"
   ```

   Profiles that use the mock login (`ci`, `poc`, the Flux `local` cluster)
   need `--set-json 'dex.connectors=[...]'` or a values file that restores
   the GitHub connector from `values.yaml`.

## Troubleshooting

`make diag` prints pods, events and the last log lines of every pod.
