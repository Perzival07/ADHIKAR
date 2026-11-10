from .base import Capabilities, LLMProvider, ProviderRequest, ProviderResult
from .mock import MockProvider
from .ollama import OllamaProvider
from .openai_compat import OpenAICompatibleProvider

# Extension point: register new vendor adapters (e.g. a cloud LLM) here; nothing outside this
# service needs to change.
REGISTRY = {
    "mock": MockProvider,
    "ollama": OllamaProvider,
    "openai_compatible": OpenAICompatibleProvider,
}

__all__ = ["REGISTRY", "Capabilities", "LLMProvider", "ProviderRequest", "ProviderResult"]
