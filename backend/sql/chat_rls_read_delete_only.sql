-- Clients may only read and delete their own chat rows. All writes go through
-- the FastAPI server key, which enforces the turn cap and one-per-day rule.
-- Run after schema.sql.

begin;

revoke all on table public.chat_sessions from anon, authenticated;
grant select, delete on table public.chat_sessions to authenticated;
drop policy if exists "chat_sessions_all_own" on public.chat_sessions;
drop policy if exists chat_sessions_select_own on public.chat_sessions;
create policy chat_sessions_select_own on public.chat_sessions
  for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists chat_sessions_delete_own on public.chat_sessions;
create policy chat_sessions_delete_own on public.chat_sessions
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on table public.chat_messages from anon, authenticated;
grant select, delete on table public.chat_messages to authenticated;
drop policy if exists "chat_messages_all_own" on public.chat_messages;
drop policy if exists chat_messages_select_own on public.chat_messages;
create policy chat_messages_select_own on public.chat_messages
  for select to authenticated using (exists (
    select 1 from public.chat_sessions session
    where session.id = chat_messages.session_id
      and session.user_id = (select auth.uid())
  ));
drop policy if exists chat_messages_delete_own on public.chat_messages;
create policy chat_messages_delete_own on public.chat_messages
  for delete to authenticated using (exists (
    select 1 from public.chat_sessions session
    where session.id = chat_messages.session_id
      and session.user_id = (select auth.uid())
  ));

commit;
