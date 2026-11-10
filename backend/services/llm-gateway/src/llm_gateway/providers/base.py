from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from typing import Any


@dataclass
class Capabilities:
    supports_json_schema: bool = False
    supports_streaming: bool = True
    max_context: int | None = None


@dataclass
class ProviderRequest:
    model: str
    messages: list[dict[str, str]]
    json_schema: dict[str, Any] | None = None
    max_tokens: int = 1024
    temperature: float | None = None
    options: dict[str, Any] = field(default_factory=dict)


@dataclass
class ProviderResult:
    text: str
    prompt_tokens: int = 0
    completion_tokens: int = 0


class LLMProvider(ABC):
    """A vendor adapter. Only llm-gateway knows about concrete providers."""

    name: str = "base"
    capabilities: Capabilities

    @abstractmethod
    async def chat(self, req: ProviderRequest) -> ProviderResult: ...

    @abstractmethod
    def stream(self, req: ProviderRequest) -> AsyncIterator[str]: ...

    @abstractmethod
    async def health(self) -> bool: ...

    async def aclose(self) -> None:  # pragma: no cover - optional hook
        return None
