from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx
import yaml

from .config import Settings
from .errors import UnknownAlias
from .providers import REGISTRY, LLMProvider


@dataclass
class AliasEntry:
    alias: str
    provider_name: str
    model: str
    provider: LLMProvider
    options: dict[str, Any] = field(default_factory=dict)
    fallback: list[str] = field(default_factory=list)


DEFAULT_CONFIG = {"aliases": {"default": {"provider": "mock"}, "recommender": {"provider": "mock"}, "translate": {"provider": "mock"}}}


class Registry:
    def __init__(self, config: dict, settings: Settings, transport: httpx.AsyncBaseTransport | None = None):
        self.entries: dict[str, AliasEntry] = {}
        for alias, spec in (config.get("aliases") or {}).items():
            kind = spec.get("provider", "mock")
            if kind not in REGISTRY:
                raise ValueError(f"alias {alias!r}: unknown provider {kind!r} (known: {sorted(REGISTRY)})")
            options = dict(spec.get("options") or {})
            if kind == "mock":
                provider: LLMProvider = REGISTRY[kind](options={**options, **({"mode": spec["mode"]} if "mode" in spec else {})})
            else:
                client = httpx.AsyncClient(
                    transport=transport, timeout=httpx.Timeout(settings.read_timeout, connect=settings.connect_timeout)
                )
                default_url = settings.ollama_base_url if kind == "ollama" else "http://host.docker.internal:8080"
                provider = REGISTRY[kind](base_url=spec.get("base_url", default_url), options=options, client=client)
            self.entries[alias] = AliasEntry(
                alias=alias, provider_name=kind, model=spec.get("model", f"{kind}-default"),
                provider=provider, options=options, fallback=list(spec.get("fallback") or []),
            )
        for e in self.entries.values():
            for f in e.fallback:
                if f not in self.entries:
                    raise ValueError(f"alias {e.alias!r}: fallback {f!r} is not a configured alias")

    @classmethod
    def from_file(cls, path: str, settings: Settings, transport=None) -> Registry:
        p = Path(path)
        config = yaml.safe_load(p.read_text()) if p.exists() else DEFAULT_CONFIG
        return cls(config or DEFAULT_CONFIG, settings, transport)

    def get(self, alias: str) -> AliasEntry:
        try:
            return self.entries[alias]
        except KeyError:
            raise UnknownAlias(f"unknown model alias {alias!r}; configured: {sorted(self.entries)}") from None

    async def aclose(self) -> None:
        for e in self.entries.values():
            await e.provider.aclose()
