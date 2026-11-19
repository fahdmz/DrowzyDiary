import asyncio
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi import BackgroundTasks
from postgrest.exceptions import APIError

from app.routers import chat
from app.schemas.chat import StartSessionRequest


class Query:
    def __init__(self, db, table):
        self.db = db
        self.table = table
        self.filters = []
        self.op = "select"
        self.payload = None

    def select(self, *_args, **_kwargs):
        return self

    def eq(self, column, value):
        self.filters.append(lambda row: row.get(column) == value)
        return self

    def gte(self, column, value):
        self.filters.append(lambda row: row.get(column) >= value)
        return self

    def order(self, *_args, **_kwargs):
        return self

    def limit(self, *_args):
        return self

    def insert(self, payload):
        self.op, self.payload = "insert", payload
        return self

    def update(self, payload):
        self.op, self.payload = "update", payload
        return self

    def execute(self):
        rows = self.db.tables[self.table]
        if self.op == "insert":
            return SimpleNamespace(data=[self.db.insert(self.table, self.payload)])
        matched = [r for r in rows if all(f(r) for f in self.filters)]
        if self.op == "update":
            self.db.log.append(("update", self.table, dict(self.payload)))
            for row in matched:
                row.update(self.payload)
        return SimpleNamespace(data=[dict(r) for r in matched])


class FakeSupabase:
    """Enforces the one-active-session-per-mode partial unique index."""

    def __init__(self, sessions=(), on_insert=None):
        self.tables = {"chat_sessions": [dict(s) for s in sessions], "chat_messages": []}
        self.log = []
        self.on_insert = on_insert

    def table(self, name):
        return Query(self, name)

    def insert(self, table, payload):
        if table == "chat_sessions":
            if self.on_insert:
                self.on_insert(self)
            row = {
                "id": f"session-{len(self.tables[table]) + 1}",
                "status": "active",
                "started_at": datetime.now(timezone.utc).isoformat(),
                **payload,
            }
            clash = any(
                s["user_id"] == row["user_id"]
                and s["checkin_mode"] == row["checkin_mode"]
                and s["status"] == "active"
                for s in self.tables[table]
            )
            if clash:
                raise APIError({"code": "23505", "message": "duplicate key"})
        else:
            row = {
                "id": f"message-{len(self.tables[table]) + 1}",
                "created_at": datetime.now(timezone.utc).isoformat(),
                "is_crisis": False,
                **payload,
            }
        self.log.append(("insert", table, row["id"]))
        self.tables[table].append(row)
        return dict(row)


class FakeRecapService:
    def __init__(self):
        self.calls = []

    async def generate_for_session(self, **kwargs):
        self.calls.append(kwargs)


def _payload():
    return StartSessionRequest(checkin_mode="night", language="en", timezone_offset_minutes=0)


def _start(sb, monkeypatch, recap_service=None):
    monkeypatch.setattr(chat, "_get_supabase", lambda: sb)
    tasks = BackgroundTasks()
    response = chat.start_session(
        _payload(), tasks, user_id="user-1", recap_service=recap_service or FakeRecapService()
    )
    return response, tasks


def test_stale_session_is_completed_before_todays_insert_and_recap_is_deferred(monkeypatch):
    yesterday = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat()
    sb = FakeSupabase(
        [{"id": "stale", "user_id": "user-1", "checkin_mode": "night",
          "status": "active", "started_at": yesterday}]
    )
    recap_service = FakeRecapService()

    response, tasks = _start(sb, monkeypatch, recap_service)

    assert response.session_id != "stale"
    completed_at = next(i for i, e in enumerate(sb.log) if e[:2] == ("update", "chat_sessions"))
    inserted_at = next(i for i, e in enumerate(sb.log) if e[:2] == ("insert", "chat_sessions"))
    assert completed_at < inserted_at
    assert sb.tables["chat_sessions"][0]["status"] == "completed"

    assert recap_service.calls == []
    asyncio.run(tasks())
    assert recap_service.calls == [{"user_id": "user-1", "session_id": "stale"}]


def test_concurrent_start_resumes_the_session_that_won_the_unique_index(monkeypatch):
    def concurrent_winner(db):
        db.on_insert = None
        db.insert("chat_sessions", {"user_id": "user-1", "checkin_mode": "night"})
        db.insert("chat_messages", {"session_id": "session-1", "sender": "ai", "text": "Hi"})

    sb = FakeSupabase(on_insert=concurrent_winner)

    response, _ = _start(sb, monkeypatch)

    active = [s for s in sb.tables["chat_sessions"] if s["status"] == "active"]
    assert len(active) == 1
    assert response.session_id == active[0]["id"]
    assert [m.text for m in response.messages] == ["Hi"]


def test_unrelated_insert_errors_are_not_swallowed(monkeypatch):
    def fail(_db):
        raise APIError({"code": "23503", "message": "fk violation"})

    with pytest.raises(APIError):
        _start(FakeSupabase(on_insert=fail), monkeypatch)
