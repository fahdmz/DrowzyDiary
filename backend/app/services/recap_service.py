"""Application service for idempotent completed-session recap generation."""

from __future__ import annotations

import asyncio
from typing import Any

from app.services.recap_generator import PROMPT_VERSION


class RecapSessionNotFoundError(RuntimeError):
    pass


class RecapService:
    def __init__(self, *, repository: Any, generator: Any) -> None:
        self.repository = repository
        self.generator = generator

    async def generate_for_session(
        self,
        *,
        user_id: str,
        session_id: str,
    ) -> dict[str, Any]:
        session = await asyncio.to_thread(
            self.repository.get_owned_completed_session, session_id, user_id
        )
        if session is None:
            raise RecapSessionNotFoundError

        existing = await asyncio.to_thread(self.repository.find_recap, session_id)
        if existing is not None:
            return existing

        messages = await asyncio.to_thread(self.repository.load_messages, session_id)
        analyses = await asyncio.to_thread(self.repository.load_analyses, session_id)
        recap = await self.generator.generate(
            checkin_mode=session["checkin_mode"],
            messages=messages,
            analyses=analyses,
        )
        return await asyncio.to_thread(
            self.repository.save_recap,
            session_id,
            recap,
            model_deployment=self.generator.deployment,
            prompt_version=PROMPT_VERSION,
        )
