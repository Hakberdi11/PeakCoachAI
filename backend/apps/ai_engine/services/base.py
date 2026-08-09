from abc import ABC, abstractmethod


class AIServiceProvider(ABC):
    """Interface implemented by any LLM backend (OpenAI, Claude, Gemini, ...).

    Application code should depend on this interface, never on a specific
    provider, so the underlying model can be swapped without refactoring
    callers.
    """

    @abstractmethod
    def generate_completion(self, prompt: str) -> str:
        raise NotImplementedError
