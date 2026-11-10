# Prompts

All prompt text lives in files here, never inline in code. Files are versioned; the active version is chosen
by config (`RECO_PROMPT_VERSION`, `RECO_EXPLAIN_PROMPT_VERSION`). A missing version fails at startup.
Literal braces in prompt files are written `{{` / `}}` because files are rendered with `str.format`.

| File | Purpose |
|---|---|
| `recommend.v1.system.md` / `.user.md` | Original long prompt. Kept for A/B comparison. |
| `recommend.v2.system.md` / `.user.md` | **Default.** Compact prompt for small (<=3B) local models: short rules, one worked example, schema restated at the end. |
| `explain.v1.*` | One scheme, deeper explanation (what, who, documents required, how to apply) for the detail screen. |
| `translate.v1.system.md` | Translation of reasons/explanations when the target language is a "pivot" language. |
| `query.v1.md` | Retrieval query built from the citizen profile. |
| `intent_keywords.yaml` | Keywords added to the retrieval query per occupation/situation. |
| `languages.yaml` | Language code -> name used inside prompts. |

## A/B testing versions
Copy `recommend.v2.*` to `recommend.v3.*`, edit, then run the eval harness (`backend/eval`) twice with
`RECO_PROMPT_VERSION=v2` and `v3` and compare the two result files.

## Guardrails (defence in depth; the prompt is the weakest layer)
1. **Deterministic eligibility** picks the candidate set; the model never sees ineligible schemes.
2. **Documents are data**: wrapped as `<doc id=".." scheme="..">`, the system prompt says so, and chunk text can
   never close or forge a `<doc>` tag (`escape_doc_text`).
3. **Flagged chunks**: ingestion flags instruction-like text ("ignore previous instructions", "system:", ...).
   They are passed with `flagged="true"` and the v2 prompt tells the model not to rely on them.
4. **Output validation** (`validate.py`) is what actually guarantees safety: unknown scheme ids, ineligible
   schemes, unknown/cross-scheme citations and duplicates are dropped; confidence is clamped; eligible always
   ranks before unknown. If nothing valid is left, the API returns rules-only results.

## Languages
`RECO_DIRECT_LANGUAGES` (default `en,hi`) are written directly by the model. Any other language is generated in
`RECO_PIVOT_LANGUAGE` (default `en`) and then translated through the `translate` model alias. If translation
fails the response keeps the pivot-language text and says so in `reason_language`. Scheme names are never translated.
A dedicated translation model (e.g. IndicTrans2) can be added later as a llm-gateway provider behind the
`translate` alias without touching this service.
