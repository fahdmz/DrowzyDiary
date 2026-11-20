import asyncio
import gc

from app.services import chat_orchestrator
from app.services.chat_orchestrator import ChatOrchestrator
from app.services.foundry_chatbot import ChatbotReply
from app.services.safety import SafetyScreen
from tests.test_chat_orchestrator import FakeAnalyzer, FakeRepository


class ClosingChatbot:
    async def respond(self, **kwargs):
        return ChatbotReply(text="Sleep well.", should_close=True)


class GatedRecapService:
    def __init__(self):
        self.gate = asyncio.Event()
        self.calls = []

    async def generate_for_session(self, **kwargs):
        await self.gate.wait()
        self.calls.append(kwargs)


def test_recap_task_is_strongly_referenced_until_it_finishes():
    repository = FakeRepository()
    repository.mark_session_completed = lambda session_id, user_id: None

    async def scenario():
        recap_service = GatedRecapService()
        orchestrator = ChatOrchestrator(
            repository=repository,
            safety_screen=SafetyScreen(),
            analyzer=FakeAnalyzer(),
            chatbot=ClosingChatbot(),
            resource_name="Healing119",
            resource_phone="119 ext. 8",
            resource_url="https://www.healing119.id",
            recap_service=recap_service,
            max_user_turns=1,
        )
        result = await orchestrator.send_message(
            user_id="user-1", session_id="session-1", text="Capek", language="id"
        )
        assert result.session_status == "completed"

        gc.collect()
        assert len(chat_orchestrator._background_tasks) == 1
        task = next(iter(chat_orchestrator._background_tasks))

        recap_service.gate.set()
        await task
        assert recap_service.calls == [{"user_id": "user-1", "session_id": "session-1"}]
        assert chat_orchestrator._background_tasks == set()

    asyncio.run(scenario())


def test_failed_recap_task_is_logged_and_released(caplog):
    class FailingRecapService:
        async def generate_for_session(self, **kwargs):
            raise RuntimeError("foundry down")

    async def scenario():
        task = chat_orchestrator.spawn_background(
            chat_orchestrator.generate_recap_best_effort(
                FailingRecapService(), "user-1", "session-1"
            )
        )
        await task
        assert chat_orchestrator._background_tasks == set()

    asyncio.run(scenario())
    assert "Best-effort recap generation failed for session session-1" in caplog.text
