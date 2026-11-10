"""Single source of truth for all cross-service data contracts.

Do not edit the copies inside services; edit this file, then run `python contracts/sync.py`.
Each service keeps an identical copy (<pkg>/contract_models.py) so no service imports another's code.
"""
from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

Gender = Literal["Male", "Female", "Other"]
MaritalStatus = Literal["Single", "Married", "Widow", "Divorced"]
StudentLevel = Literal["None", "School (1-10)", "Post-Matric (11-12/ITI)", "Higher Ed"]
SocialCategory = Literal["General", "OBC", "SC", "ST", "EWS"]
RationCard = Literal["Antyodaya (AAY)", "BPL", "Priority (PHH)", "APL", "None"]
IncomeRange = Literal["< 1 Lakh", "1 - 2.5 Lakh", "2.5 - 5 Lakh", "> 5 Lakh"]
Disability = Literal["None", "< 40%", "40%+ (Divyangjan)"]
SourceType = Literal["corpus", "pdf", "web", "manual"]
EligibilityStatus = Literal["eligible", "ineligible", "unknown"]


class ErrorResponse(BaseModel):
    detail: str


# ----------------------------------------------------------------- shared data
class CitizenProfile(BaseModel):
    """Mirrors CitizenProfile.toJson() in lib/core/models/citizen_profile.dart.

    extra="forbid": the app must never send name/phone/email to the backend.
    """

    model_config = ConfigDict(extra="forbid")

    state: str = "Uttar Pradesh"
    district: str = ""
    age: int = Field(35, ge=0, le=120)
    gender: Gender = "Male"
    maritalStatus: MaritalStatus = "Married"
    occupation: str = "Citizen"
    landHoldingAcres: float = Field(0.0, ge=0)
    artisanTrade: str = ""
    studentLevel: StudentLevel = "None"
    socialCategory: SocialCategory = "General"
    rationCard: RationCard = "None"
    annualIncomeRange: IncomeRange = "1 - 2.5 Lakh"
    disabilityStatus: Disability = "None"
    hasGirlChildUnder10: bool = False


class SchemeDocMeta(BaseModel):
    scheme_id: str
    name: str
    state_scope: str = "All"  # "All" or a state / UT name
    is_central: bool = True
    category: str = ""
    gender_eligibility: Literal["All", "Female", "Male"] = "All"
    income_ceiling: str = "No Limit"
    min_age: int | None = None
    max_age: int | None = None
    education_level: str = "All"
    official_portal_url: str = ""
    last_verified_date: str = ""
    language: str = "en"
    source_type: SourceType = "corpus"
    status: Literal["verified", "unverified"] = "verified"


class Chunk(BaseModel):
    chunk_id: str
    scheme_id: str
    text: str
    section: str = ""
    page: int | None = None
    source: str = ""
    meta: SchemeDocMeta | None = None
    score: float = 0.0
    flagged: bool = False  # contains instruction-like text (possible prompt injection)


class EligibilityResult(BaseModel):
    scheme_id: str
    status: EligibilityStatus
    score: float = Field(0.0, ge=0, le=1)  # rule confidence; >= 0.5 <=> eligible
    reasons: list[str] = []
    missing_fields: list[str] = []


class Citation(BaseModel):
    chunk_id: str
    quote: str = ""
    section: str = ""  # section of the source document (e.g. "Benefit"), for "Sources" chips in the app
    url: str = ""  # official portal URL of the scheme, if known


class Recommendation(BaseModel):
    scheme_id: str
    name: str = ""
    rank: int = Field(..., ge=1)
    confidence: float = Field(..., ge=0, le=1)
    reason: str
    reason_language: str = "en"
    citations: list[Citation] = []
    missing_info: list[str] = []
    eligibility_status: Literal["eligible", "unknown"] = "eligible"


# ----------------------------------------------------------------- llm-gateway
class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    model_alias: str
    messages: list[ChatMessage] = Field(..., min_length=1)
    json_schema: dict[str, Any] | None = None
    max_tokens: int = Field(1024, ge=1, le=32768)
    temperature: float | None = Field(None, ge=0, le=2)
    stream: bool = False


class Usage(BaseModel):
    prompt_tokens: int = 0
    completion_tokens: int = 0


class ChatResponse(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    text: str
    json_: dict[str, Any] | None = Field(None, alias="json")
    usage: Usage = Usage()
    provider: str
    model: str


class ModelAliasInfo(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    alias: str
    provider: str
    model: str
    supports_json_schema: bool = False
    supports_streaming: bool = False
    max_context: int | None = None


class ModelsResponse(BaseModel):
    aliases: list[ModelAliasInfo]


# ----------------------------------------------------------- embedding-service
class EmbedRequest(BaseModel):
    texts: list[str] = Field(..., min_length=1)
    kind: Literal["query", "document"] = "document"


class EmbedResponse(BaseModel):
    model_config = ConfigDict(protected_namespaces=())

    vectors: list[list[float]]
    dim: int
    model_id: str
    truncated: list[bool] = []


# ----------------------------------------------------------- ingestion-service
class IngestRequest(BaseModel):
    path: str | None = None
    force: bool = False


class FileError(BaseModel):
    file: str
    error: str


class IngestStatus(BaseModel):
    state: Literal["idle", "running", "done", "error"] = "idle"
    started_at: str | None = None
    finished_at: str | None = None
    files_total: int = 0
    files_processed: int = 0
    files_unchanged: int = 0
    chunks_added: int = 0
    chunks_deleted: int = 0
    collection: str | None = None
    errors: list[FileError] = []


class DeleteDocResponse(BaseModel):
    scheme_id: str
    chunks_deleted: int


# ------------------------------------------------------------ retrieval-service
class SearchFilters(BaseModel):
    scheme_ids: list[str] | None = None
    state: str | None = None
    include_central: bool = True
    language: str | None = None


class SearchRequest(BaseModel):
    query: str = Field(..., min_length=1)
    filters: SearchFilters = SearchFilters()
    top_k: int = Field(10, ge=1, le=100)
    max_chunks_per_scheme: int = Field(2, ge=1, le=10)


class SearchResponse(BaseModel):
    chunks: list[Chunk]


# --------------------------------------------------------- eligibility-service
class EligibilityRequest(BaseModel):
    profile: CitizenProfile
    scheme_ids: list[str] | None = None


class EligibilityResponse(BaseModel):
    results: list[EligibilityResult]


# ------------------------------------------------------ recommendation-service
class RecommendationRequest(BaseModel):
    profile: CitizenProfile
    language: str = "en"
    top_n: int = Field(5, ge=1, le=20)
    include_citations: bool = True


class RecommendationResponse(BaseModel):
    recommendations: list[Recommendation]
    more: list[Recommendation] = []  # eligible schemes beyond top_n
    mode: Literal["rag", "rules_only"]
    trace_id: str
    fallback_reason: str | None = None  # why rules_only was used (e.g. "llm_unavailable")


class ExplainRequest(BaseModel):
    profile: CitizenProfile
    scheme_id: str = Field(..., min_length=1)
    language: str = "en"


class ExplainResponse(BaseModel):
    scheme_id: str
    name: str = ""
    eligibility_status: EligibilityStatus
    eligibility_reason: str = ""  # from the deterministic rules (authoritative)
    explanation: str
    documents_required: list[str] = []
    how_to_apply: list[str] = []
    citations: list[Citation] = []
    reason_language: str = "en"
    mode: Literal["rag", "rules_only"]
    trace_id: str
    fallback_reason: str | None = None
