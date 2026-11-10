# ADR 0002: Rules decide eligibility; the LLM only ranks and explains
**Status:** accepted
**Context:** a small (<=3B) local model is cheap but unreliable at reasoning over eligibility criteria.
**Decision:** eligibility-service (declarative rules, parity-tested with the app) is authoritative. The LLM sees only
eligible schemes and its output is validated; failures fall back to rules-only answers.
**Consequences:** no hallucinated entitlements reach users; quality of explanations depends on the model.
