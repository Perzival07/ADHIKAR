from __future__ import annotations

from abc import ABC, abstractmethod


class EmbeddingProvider(ABC):
    """Vendor adapter. Only embedding-service knows which embedding model is in use."""

    name: str = "base"

    @abstractmethod
    async def embed(self, texts: list[str], kind: str) -> list[list[float]]: ...

    @abstractmethod
    async def info(self) -> tuple[str, int]:
        """Return (model_id, dim). model_id embeds the model name and dim so collections never mix."""

    @abstractmethod
    async def ready(self) -> tuple[bool, str]: ...

    async def aclose(self) -> None:  # pragma: no cover
        return None
