# Runbook

Useful first commands: `kubectl -n adhikar get pods`, `kubectl -n adhikar logs deploy/<svc> | grep <request-id>`
(every log line carries `request_id`; the API returns it as `X-Request-ID` and `trace_id`).

| Alert / symptom | Likely cause | Action |
|---|---|---|
| AdhikarApiErrorRateHigh | a dependency down, bad deploy | `kubectl rollout status`; check `/ready` of reco (eligibility down = 503s); roll back with `rollout undo` |
| AdhikarRulesOnlyFallbackHigh | LLM / retrieval degraded | `reco_fallback_reason_*_total` says which; check llm-gateway `/ready` (per-alias checks) and model servers |
| AdhikarCircuitOpen | a dependency failed 5x in a row | breaker retries after 30 s automatically; fix the dependency, nothing to reset |
| AdhikarLlmQueueRejections | LLM saturated | add model servers; temporarily lower anonymous rate limit |
| AdhikarRecommendationLatencyHigh | LLM slow or cache hit rate fell | check `reco_stage_seconds` (which stage), `reco_cache_hit_total` |
| AdhikarIngestFailed | bad document / embedding down | `kubectl logs job/<ingest-job> -c ingest`: per-file errors are listed; re-run with `create job --from=cronjob/ingest` |
| Users get 401 after a deploy | JWT key changed or missing | `AUTH_JWT_PRIVATE_KEY` must be identical on all auth pods; users re-login after a deliberate rotation |
| auth pods stuck in Init | Postgres unreachable / migration error | `kubectl logs <pod> -c migrate` |
| HPA "unable to get metrics" | metrics-server missing | install metrics-server |
| New pod's first requests refused | NetworkPolicy not yet programmed for the new pod IP (a few seconds on some CNIs) | transient; readiness probes keep traffic away from such pods |

## Routine operations
- **New / updated schemes**: update `backend/data/scheme_docs` -> new `scheme-docs` image tag -> roll out eligibility
  + run the ingest job (it clears the recommendation cache when something changed).
- **Clear the cache manually**: `POST /v1/admin/cache/clear` with `RECO_ADMIN_TOKEN`, from inside the cluster.
- **Change the LLM**: edit the `llm-models` ConfigMap (`deploy/k8s/base/models.yaml`), apply, run the eval harness.
