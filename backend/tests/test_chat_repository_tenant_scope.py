from types import SimpleNamespace

from app.services.chat_repository import SupabaseChatRepository


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

    def gte(self, column, value):
        self.filters.append(("gte", column, value))
        return self

    def in_(self, column, values):
        self.filters.append(("in", column, values))
        return self

    def order(self, *args, **kwargs):
        return self

    def limit(self, value):
        return self

    def execute(self):
        self.client.calls.append(self)
        return SimpleNamespace(data=[])


class FakeSupabase:
    def __init__(self):
        self.calls = []

    def table(self, name):
        return Query(self, name)


def test_historical_analysis_is_scoped_by_user_join_without_session_id_list():
    sb = FakeSupabase()
    repository = SupabaseChatRepository(sb)

    repository.load_chat_context("user-1", "session-1")

    assert not any(call.table == "chat_sessions" for call in sb.calls)
    analysis_query = next(call for call in sb.calls if call.table == "message_analyses")
    assert "chat_messages!inner(chat_sessions!inner(user_id))" in analysis_query.columns
    assert ("eq", "chat_messages.chat_sessions.user_id", "user-1") in analysis_query.filters
    assert not any(kind == "in" for kind, *_ in analysis_query.filters)
