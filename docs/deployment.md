# Deployment (Kubernetes)

Manifests: `deploy/k8s` (Kustomize). `base/` is production-shaped; `overlays/dev` and `overlays/prod` adjust it.

## Cluster prerequisites
| Component | Why | Without it |
|---|---|---|
| ingress-nginx | public routing, TLS, body/rps limits | no external access (port-forward only) |
| cert-manager (`letsencrypt-prod` ClusterIssuer) | TLS certificates (prod overlay) | create `api-tls` secret yourself |
| metrics-server | HPA autoscaling on CPU | HPAs report "unable to get metrics" and never scale |
| kube-prometheus-stack | `ServiceMonitor` + alerts (prod overlay component) | remove `components/monitoring` from the prod overlay |
| NetworkPolicy-capable CNI (Calico, Cilium, kube-router...) | zero-trust between pods | policies are ignored |
| Default StorageClass | Qdrant, ingest manifest, (dev) Postgres | PVCs stay Pending |
| Managed Postgres 14+ | auth-service accounts (prod) | use the dev component only for testing |

## First deployment (prod)
1. **Images**: tag a release (`git tag v1.0.0 && git push --tags`). The `release` workflow builds, scans and pushes
   every image to GHCR and uploads `adhikar-v1.0.0.yaml` (prod manifests pinned to that version).
2. **Secrets** (never committed): create `auth-secrets`, `reco-secrets`, `adhikar-shared` in namespace `adhikar`
   with the keys in `deploy/k8s/overlays/prod/secrets.example.env`, ideally via External Secrets / Sealed Secrets.
   - JWT key: `python -m auth_service gen-key --base64`
   - OTP secret / tokens: 32+ random bytes, e.g. `python -c "import secrets;print(secrets.token_hex(32))"`
   - SMTP: a transactional email provider (production refuses the console backend).
3. **Hosts**: replace `api.adhikar.example` / `app.adhikar.example` in the prod overlay (Ingress + CORS literals).
4. **Apply**: `kubectl apply -f adhikar-v1.0.0.yaml` (or `kubectl apply -k deploy/k8s/overlays/prod`).
   auth-service runs its database migrations in an init container under a Postgres advisory lock, so any number
   of replicas can start at once.
5. **Load the knowledge base**: `kubectl -n adhikar create job --from=cronjob/ingest ingest-now`, then
   `kubectl -n adhikar logs -f job/ingest-now -c ingest` (expects `"state": "done"` and `cache clear: HTTP 200`).
6. **Verify**: `kubectl -n adhikar get pods` (all Ready), then from outside
   `curl https://api.<host>/.well-known/jwks.json` and a test recommendation.

## Upgrades and rollback
- Rolling updates with `maxUnavailable: 0`, readiness gates and a pre-stop delay: verified to drop no requests.
- Roll back: `kubectl -n adhikar rollout undo deploy/<service>` (or re-apply the previous release's manifest).
- Database migrations must stay backward compatible for one release (expand -> deploy -> contract), because old and
  new pods run side by side during a rollout.
- Updating scheme documents = build a new `scheme-docs` image tag, roll out, and run the ingest job.

## Local cluster (dev overlay)
```sh
cd backend
make images            # builds adhikar/<service>:local
make k8s-dev-secrets   # random secrets into deploy/k8s/overlays/dev/secrets/ (git-ignored)
kubectl apply -k ../deploy/k8s/overlays/dev
```
On kind/k3s load the local images into the cluster first (`kind load docker-image ...` / `ctr images import`).
The dev overlay runs single replicas, an in-cluster Postgres, console OTP delivery and demo users.

## Configuration
Non-secret settings live in the `adhikar-config` ConfigMap (one `envFrom` for every pod; each service only reads its
own prefix: `AUTH_`, `RECO_`, `RETRIEVAL_`, `INGEST_`, `ELIG_`, `EMBED_`, `LLMGW_`). Changing it rolls the pods
because the ConfigMap name carries a content hash. The LLM routing file is the `llm-models` ConfigMap
(`deploy/k8s/base/models.yaml`, kept identical to `backend/services/llm-gateway/models.yaml` by a test).
