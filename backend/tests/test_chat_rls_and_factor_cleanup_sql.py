from pathlib import Path

SQL_DIR = Path(__file__).parents[1] / "sql"


def _sql(name):
    return " ".join((SQL_DIR / name).read_text(encoding="utf-8").casefold().split())


def test_chat_tables_allow_clients_only_select_and_delete():
    sql = _sql("chat_rls_read_delete_only.sql")
    for table in ("chat_sessions", "chat_messages"):
        assert f'drop policy if exists "{table}_all_own" on public.{table};' in sql
        assert f"revoke all on table public.{table} from anon, authenticated;" in sql
        assert f"grant select, delete on table public.{table} to authenticated;" in sql
        assert f"create policy {table}_select_own on public.{table} for select" in sql
        assert f"create policy {table}_delete_own on public.{table} for delete" in sql
    assert "for all" not in sql
    assert "for insert" not in sql and "for update" not in sql


def test_orphaned_sleep_factors_are_removed_by_statement_trigger():
    sql = _sql("sleep_factor_orphan_cleanup.sql")
    assert "after delete on public.sleep_factor_occurrences" in sql
    assert "referencing old table as deleted_occurrences" in sql
    assert "for each statement execute function public.delete_orphaned_sleep_factors()" in sql
    assert sql.count("delete from public.sleep_factors factor") == 2


def test_delete_today_script_relies_on_cascade():
    sql = _sql("delete_today_checkins.sql")
    assert "set null" not in sql
    assert "delete from public.sleep_factor_occurrences" not in sql
