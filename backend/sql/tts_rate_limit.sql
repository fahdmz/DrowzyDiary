-- Per-user rate limit for the google-tts Edge Function.
-- Run after schema.sql. Only the Edge Function's service role may call it.

begin;

create table if not exists public.tts_rate_limits (
  user_id uuid primary key references auth.users (id) on delete cascade,
  window_start timestamptz not null,
  request_count bigint not null
);

alter table public.tts_rate_limits enable row level security;
revoke all on public.tts_rate_limits from anon, authenticated;

create or replace function public.consume_tts_rate_limit(
  p_user_id uuid,
  p_limit integer,
  p_window_seconds integer
)
returns table (allowed boolean, retry_after_seconds integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_window_start timestamptz;
  v_count bigint;
begin
  insert into public.tts_rate_limits as r (user_id, window_start, request_count)
  values (p_user_id, now(), 1)
  on conflict (user_id) do update set
    window_start = case
      when r.window_start <= now() - make_interval(secs => p_window_seconds)
        then now() else r.window_start end,
    request_count = case
      when r.window_start <= now() - make_interval(secs => p_window_seconds)
        then 1 else least(r.request_count + 1, p_limit + 1) end
  returning r.window_start, r.request_count into v_window_start, v_count;

  allowed := v_count <= p_limit;
  retry_after_seconds := case
    when allowed then 0
    else greatest(1, ceil(extract(epoch from
      (v_window_start + make_interval(secs => p_window_seconds) - now()))))::integer
  end;
  return next;
end;
$$;

revoke all on function public.consume_tts_rate_limit(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_tts_rate_limit(uuid, integer, integer)
  to service_role;

commit;
