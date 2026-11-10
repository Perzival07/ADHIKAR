from __future__ import annotations

import asyncio
import os
from pathlib import Path

from .base import EmbeddingProvider


class SentenceTransformersProvider(EmbeddingProvider):
    """Loads a LOCAL sentence-transformers model folder. Never downloads anything."""

    name = "sentence_transformers"

    def __init__(self, model_path: str, device: str = "cpu", query_prefix: str = "", document_prefix: str = ""):
        self.model_path = model_path
        self.device = device
        self.query_prefix = query_prefix
        self.document_prefix = document_prefix
        self._model = None
        self._dim: int | None = None

    def _check_path(self) -> str | None:
        if not self.model_path:
            return "EMBED_MODEL_PATH is not set (point it at a local model folder, e.g. bge-m3)"
        if not Path(self.model_path).exists():
            return f"model path does not exist: {self.model_path}"
        return None

    def _load(self):
        if self._model is None:
            err = self._check_path()
            if err:
                raise RuntimeError(err)
            os.environ.setdefault("HF_HUB_OFFLINE", "1")
            os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
            from sentence_transformers import SentenceTransformer  # lazy: heavy, optional dependency

            self._model = SentenceTransformer(self.model_path, device=self.device)
            self._dim = int(self._model.get_sentence_embedding_dimension())
        return self._model

    async def embed(self, texts: list[str], kind: str) -> list[list[float]]:
        prefix = self.query_prefix if kind == "query" else self.document_prefix
        batch = [prefix + t for t in texts]

        def run():
            return self._load().encode(batch, normalize_embeddings=True, convert_to_numpy=True).tolist()

        return await asyncio.to_thread(run)

    async def info(self) -> tuple[str, int]:
        await asyncio.to_thread(self._load)
        return f"st-{Path(self.model_path).name}-{self._dim}", int(self._dim or 0)

    async def ready(self) -> tuple[bool, str]:
        err = self._check_path()
        if err:
            return False, err
        try:
            import sentence_transformers  # noqa: F401
        except ImportError:
            return False, "sentence-transformers is not installed (pip install sentence-transformers)"
        return True, "ok"
