from datetime import datetime, timezone
from types import SimpleNamespace

from app.schemas.analysis import AnalysisResult, AnalysisSource, Emotion, RiskLevel
from app.services.chat_repository import SupabaseChatRepository


class Query:
    def __init__(self, client, table):
        self.client = client
        self.table = table
        self.operation = None
        self.payload = None
        self.filters = []
        self.limit_value = None
        self.columns = None

    def select(self, columns, **kwargs):
        self.operation = "select"
        self.columns = columns
        return self

    def insert(self, payload):
        self.operation = "insert"
        self.payload = payload
        return self

    def update(self, payload):
        self.operation = "update"
        self.payload = payload
        return self

    def eq(self, column, value):
        self.filters.append(("eq", column, value))
        return self

    def gte(self, column, value):
        self.filters.append(("gte", column, value))
        return self

    def in_(self, column, values):
        self.filters.append(("in", column, values))
        return self

    def order(self, column, **kwargs):
        return self

    def limit(self, value):
        self.limit_value = value
        return self

    def execute(self):
        self.client.calls.append(self)
        queue = self.client.responses.get((self.table, self.operation), [])
        data = queue.pop(0) if queue else []
        return SimpleNamespace(data=data)


class FakeSupabase:
    def __init__(self, responses=None):
        self.responses = responses or {}
        self.calls = []

    def table(self, name):
        return Query(self, name)


def analysis():
    return AnalysisResult(
        emotion=Emotion.SADNESS,
        domains=[],
        sleep_substances=[],
        sleep_hours=5.5,
        wake_time="06:30",
        confidence=0.812,
        source=AnalysisSource.LOCAL,
        risk_level=RiskLevel.NONE,
        emotion_scores={"sadness": 0.812},
        model_id="local/model",
        model_revision="revision",
    )


def test_owned_session_lookup_scopes_service_role_query_by_session_and_user():
    sb = FakeSupabase({("chat_sessions", "select"): [[{"id": "session-1"}]]})

    row = SupabaseChatRepository(sb).get_owned_session("session-1", "user-1")

    assert row["id"] == "session-1"
    assert ("eq", "id", "session-1") in sb.calls[0].filters
    assert ("eq", "user_id", "user-1") in sb.calls[0].filters


def test_analysis_insert_uses_canonical_json_values_and_foreign_keys():
    sb = FakeSupabase()

    SupabaseChatRepository(sb).save_analysis("message-1", "session-1", analysis())

    payload = sb.calls[0].payload
    assert payload["message_id"] == "message-1"
    assert payload["session_id"] == "session-1"
    assert payload["emotion"] == "sadness"
    assert payload["source"] == "local"
    assert payload["wake_time"] == "06:30"


def test_context_queries_are_bounded_and_historical_analysis_is_aggregated():
    responses = {
        ("chat_messages", "select"): [[{"sender": "user", "text": "latest"}]],
        ("session_recaps", "select"): [[{"title": "Kemarin", "summary": "Berat"}]],
        ("message_analyses", "select"): [[{
            "emotion": "sadness",
            "domains": ["work"],
            "sleep_substances": ["caffeine"],
            "sleep_hours": 5,
            "chat_messages": {"chat_sessions": {"user_id": "user-1"}},
        }]],
    }
    sb = FakeSupabase(responses)
    repository = SupabaseChatRepository(
        sb,
        message_limit=12,
        recap_limit=3,
        lookback_days=14,
        now_factory=lambda: datetime(2026, 7, 17, tzinfo=timezone.utc),
    )

    context = repository.load_chat_context("user-1", "session-1")

    message_query, recap_query, analysis_query = sb.calls
    assert message_query.limit_value == 12
    assert recap_query.limit_value == 3
    assert "chat_messages!inner(chat_sessions!inner(user_id))" in analysis_query.columns
    assert ("eq", "chat_messages.chat_sessions.user_id", "user-1") in analysis_query.filters
    assert not any(item[0] == "in" for item in analysis_query.filters)
    assert any(item[:2] == ("gte", "created_at") for item in analysis_query.filters)
    assert context["emotional_trends"]["emotion_counts"] == {"sadness": 1}


def test_mark_session_crisis_scopes_update_by_session_and_user():
    sb = FakeSupabase()

    SupabaseChatRepository(sb).mark_session_crisis("session-1", "user-1")

    update = sb.calls[0]
    assert (update.table, update.operation) == ("chat_sessions", "update")
    assert ("eq", "id", "session-1") in update.filters
    assert ("eq", "user_id", "user-1") in update.filters


def test_mark_session_completed_scopes_update_by_session_and_user():
    sb = FakeSupabase({("chat_messages", "select"): [[{"text": "first"}]]})

    SupabaseChatRepository(sb).mark_session_completed("session-1", "user-1")

    update = next(call for call in sb.calls if call.operation == "update")
    assert update.table == "chat_sessions"
    assert update.payload["preview"] == "first"
    assert ("eq", "id", "session-1") in update.filters
    assert ("eq", "user_id", "user-1") in update.filters
