# ADR 0003: Kubernetes with Kustomize
**Status:** accepted
**Decision:** deploy on Kubernetes; plain YAML with a production-shaped base and dev/prod overlays (no Helm templating).
Compose remains for local development and CI end-to-end tests.
**Consequences:** HPA, PDBs, NetworkPolicies, rolling updates and Pod Security are first-class; operators need a cluster
with ingress-nginx, metrics-server and (optionally) the Prometheus Operator.
