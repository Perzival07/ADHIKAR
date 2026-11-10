# Scheme documents folder

This folder is the knowledge base for the RAG system. `ingestion-service` reads it; `eligibility-service`
reads the front-matter metadata. Drop files here, then run `make ingest` (or `POST /v1/ingest`).

## Layouts (both can be mixed)

### 1. One file per scheme
```
<scheme_id>.md          English (language: en)
<scheme_id>.hi.md       Hindi (optional language suffix: .hi, .mr, .ta, ...)
```
The file starts with YAML front-matter that matches `contracts/schemas/SchemeDocMeta.json`:

```markdown
---
scheme_id: "pm_kisan"
name: "PM-KISAN"
state_scope: "All"          # "All" or a state / UT name
is_central: true
category: "Agriculture"
gender_eligibility: "All"   # All | Female | Male
income_ceiling: "No Limit"
min_age: 18
max_age: null
education_level: "All"
official_portal_url: "https://pmkisan.gov.in"
last_verified_date: "2025-2026"
language: "en"
source_type: "corpus"       # corpus | pdf | web | manual
status: "verified"          # verified | unverified
---
# Body: markdown with `##` section headings (Summary, Benefit, Eligibility, ...)
```

### 2. One folder per scheme (for official PDFs and other files)
```
<scheme_id>/
  meta.yaml                 same fields as the front-matter above (without the --- lines)
  guidelines.pdf
  faq.md
  gazette-notification.docx
  notice.html
  notes.txt
```
Every file in the folder inherits `meta.yaml`. Supported types: `.md .txt .pdf .docx .html`.
Language suffixes work per file (`faq.hi.md`).

## Rules
- Files without metadata (no front-matter / no `meta.yaml`) are ingested with `status: unverified` and are
  **never recommended** until metadata exists.
- Text is treated strictly as data. Keep official wording; do not add instructions for the AI.
- Re-ingesting unchanged files is a no-op; edited files replace their old chunks; deleted files remove theirs.

## Generating from the app's corpus
`lib/data/schemes_corpus.dart` can be exported with `dart run tool/export_scheme_docs.dart [outDir]`
(default: this folder). The output is deterministic, so re-running produces byte-identical files.
