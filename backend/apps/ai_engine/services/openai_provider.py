from django.conf import settings
from openai import OpenAI

from .base import AIServiceProvider


class OpenAIProvider(AIServiceProvider):
    """OpenAI-backed implementation of AIServiceProvider."""

    def __init__(self):
        self.api_key = settings.OPENAI_API_KEY
        self.model = settings.OPENAI_MODEL
        self._client = OpenAI(api_key=self.api_key) if self.api_key else None

    def generate_completion(self, prompt: str) -> str:
        if not self._client:
            raise RuntimeError('OPENAI_API_KEY is not configured.')

        response = self._client.chat.completions.create(
            model=self.model,
            messages=[{'role': 'user', 'content': prompt}],
            temperature=0.4,
            response_format={'type': 'json_object'},
        )
        return response.choices[0].message.content
