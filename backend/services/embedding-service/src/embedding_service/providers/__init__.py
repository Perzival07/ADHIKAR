from __future__ import annotations

import httpx

from ..config import Settings
from .base import EmbeddingProvider
from .hash_provider import HashProvider
from .ollama_provider import OllamaEmbeddingProvider
from .st_provider import SentenceTransformersProvider


def build_provider(s: Settings, transport: httpx.AsyncBaseTransport | None = None) -> EmbeddingProvider:
    if s.provider == "hash":
        return HashProvider(s.hash_dim)
    if s.provider == "sentence_transformers":
        return SentenceTransformersProvider(s.model_path, s.device, s.query_prefix, s.document_prefix)
    if s.provider == "ollama":
        return OllamaEmbeddingProvider(
            s.ollama_base_url, s.ollama_model, httpx.AsyncClient(transport=transport, timeout=s.timeout),
            s.timeout, s.query_prefix, s.document_prefix,
        )
    raise ValueError(f"unknown EMBED_PROVIDER {s.provider!r} (hash | sentence_transformers | ollama)")


__all__ = ["EmbeddingProvider", "build_provider"]
