from datetime import datetime, timezone
from types import SimpleNamespace

from app.services.dashboard import SupabaseDashboardRepository


class Query:
    def __init__(self, client, table):
        self.client = client
        self.table = table
        self.filters = []
        self.columns = None

    def select(self, columns):
        self.columns = columns
        return self

    def eq(self, column, value):
        self.filters.append(("eq", column, value))
        return self

    def in_(self, column, values):
        self.filters.append(("in", column, values))
        return self

    def gte(self, column, value):
        self.filters.append(("gte", column, value))
        return self

    def order(self, column, **kwargs):
        return self

    def execute(self):
        self.client.queries.append(self)
        return SimpleNamespace(data=self.client.responses[self.table].pop(0))


class FakeSupabase:
    def __init__(self):
        self.responses = {
            "message_analyses": [[{
                "session_id": "session-1",
                "sleep_hours": 7.5,
                "wake_time": "06:30",
                "created_at": "2026-07-17T01:00:00+00:00",
                "chat_messages": {"chat_sessions": {"user_id": "user-1"}},
            }]],
        }
        self.queries = []

    def table(self, name):
        return Query(self, name)


def test_weekly_sleep_repository_scopes_analyses_by_user_join():
    sb = FakeSupabase()
    since = datetime(2026, 7, 11, 17, 0, tzinfo=timezone.utc)

    rows = SupabaseDashboardRepository(sb).load_sleep_analyses(
        user_id="user-1",
        since=since,
    )

    (analysis_query,) = sb.queries
    assert analysis_query.table == "message_analyses"
    assert "chat_messages!inner(chat_sessions!inner(user_id))" in analysis_query.columns
    assert ("eq", "chat_messages.chat_sessions.user_id", "user-1") in analysis_query.filters
    assert not any(kind == "in" for kind, *_ in analysis_query.filters)
    assert ("gte", "created_at", since.isoformat()) in analysis_query.filters
    assert rows == [{
        "session_id": "session-1",
        "sleep_hours": 7.5,
        "wake_time": "06:30",
        "created_at": "2026-07-17T01:00:00+00:00",
    }]
