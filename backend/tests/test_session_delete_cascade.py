import re
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.routers import recaps

SQL_DIR = Path(__file__).parents[1] / "sql"


def _sql(name):
    return (SQL_DIR / name).read_text(encoding="utf-8").casefold()


def test_every_session_or_message_foreign_key_cascades_once_migrations_run():
    """Any FK to chat_sessions/chat_messages declared without cascade must be
    re-declared with ON DELETE CASCADE by session_delete_cascade.sql."""
    migration = _sql("session_delete_cascade.sql")
    non_cascading = []
    for name in ("schema.sql", "ai_emotional_memory.sql", "chat_idempotency.sql"):
        for match in re.finditer(
            r"references public\.(chat_sessions|chat_messages)\s*\([^)]*\)\s*on delete (\w+(?: \w+)?)",
            _sql(name),
        ):
            if match.group(2) != "cascade":
                non_cascading.append(match.group(0))

    assert len(non_cascading) == 3
    for table, column in [
        ("sleep_factor_occurrences", "session_id"),
        ("sleep_factor_occurrences", "message_id"),
        ("sleep_logs", "session_id"),
    ]:
        assert f"('{table}', '{column}'," in migration
    assert "on delete cascade" in migration
    assert "'sleep_factor_occurrences_message_fkey'" in migration
    assert "begin;" in migration and "commit;" in migration


class Query:
    def __init__(self, sb, table):
        self.sb, self.table, self.filters, self.op = sb, table, [], "select"

    def select(self, *_args):
        return self

    def delete(self):
        self.op = "delete"
        return self

    def eq(self, column, value):
        self.filters.append((column, value))
        return self

    def limit(self, *_args):
        return self

    def execute(self):
        self.sb.calls.append((self.op, self.table, self.filters))
        return SimpleNamespace(data=self.sb.recap_rows if self.op == "select" else [])


class FakeSupabase:
    def __init__(self, recap_rows):
        self.recap_rows = recap_rows
        self.calls = []

    def table(self, name):
        return Query(self, name)


def test_delete_recap_deletes_owned_session_row(monkeypatch):
    sb = FakeSupabase([{"session_id": "session-1", "chat_sessions": {"user_id": "user-1"}}])
    monkeypatch.setattr(recaps, "get_supabase", lambda: sb)

    recaps.delete_recap("recap-1", user_id="user-1")

    lookup, delete = sb.calls
    assert ("chat_sessions.user_id", "user-1") in lookup[2]
    assert delete == ("delete", "chat_sessions", [("id", "session-1"), ("user_id", "user-1")])


def test_delete_recap_of_another_user_is_404_and_deletes_nothing(monkeypatch):
    sb = FakeSupabase([])
    monkeypatch.setattr(recaps, "get_supabase", lambda: sb)

    with pytest.raises(HTTPException) as raised:
        recaps.delete_recap("recap-1", user_id="user-2")

    assert raised.value.status_code == 404
    assert [call[0] for call in sb.calls] == ["select"]
