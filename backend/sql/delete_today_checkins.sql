-- Delete today's PillowTalk check-ins for ONE Supabase auth user.
--
-- USAGE
--   1. Copy the user's id from Supabase Dashboard > Authentication > Users.
--   2. Paste it over the all-zero placeholder in the `params` table below
--      (it is the only place the id appears) — do NOT commit the edited file.
--   3. Run the whole script in the Supabase SQL Editor (or psql).
--
-- The placeholder is rejected by the guard below, so running the script
-- unedited does nothing.
--
-- "Today" is calculated in Asia/Jakarta, matching the app user's local day.
-- Deleting chat_sessions cascades to chat_messages, message_analyses, and
-- session_recaps. sleep_factor_occurrences are deleted explicitly first
-- because their session_id foreign key uses ON DELETE SET NULL.

begin;

create temporary table params on commit drop as
select '00000000-0000-0000-0000-000000000000'::uuid as user_id;  -- <-- EDIT ME

do $$
declare
  target_user_id uuid := (select user_id from params);
begin
  if target_user_id = '00000000-0000-0000-0000-000000000000'::uuid then
    raise exception 'Edit params.user_id at the top of this script first';
  end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    raise exception 'No auth.users row found for %', target_user_id;
  end if;
end
$$;

create temporary table today_sessions_to_delete on commit drop as
select id
from public.chat_sessions
where user_id = (select user_id from params)
  and started_at >= date_trunc('day', now() at time zone 'Asia/Jakarta') at time zone 'Asia/Jakarta'
  and started_at < (date_trunc('day', now() at time zone 'Asia/Jakarta') + interval '1 day') at time zone 'Asia/Jakarta';

delete from public.sleep_factor_occurrences occurrence
where occurrence.session_id in (
  select id from today_sessions_to_delete
);

delete from public.chat_sessions session
where session.id in (
  select id from today_sessions_to_delete
);

commit;

-- Optional check after running (paste the same user id here):
--
-- select count(*) as remaining_today_checkins
-- from public.chat_sessions
-- where user_id = '<user id>'
--   and started_at >= date_trunc('day', now() at time zone 'Asia/Jakarta') at time zone 'Asia/Jakarta'
--   and started_at < (date_trunc('day', now() at time zone 'Asia/Jakarta') + interval '1 day') at time zone 'Asia/Jakarta';
