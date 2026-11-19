-- Deleting a chat session must delete everything derived from it.
-- Run after schema.sql, ai_emotional_memory.sql and chat_idempotency.sql.
--
-- chat_messages, message_analyses, safety_events, session_recaps and the
-- idempotency columns already go with the session. These three foreign keys
-- were ON DELETE SET NULL, which left factor occurrences (still shown on the
-- Profile dashboard) and sleep logs behind after a user deleted an entry.
-- Constraint names match the ones ai_emotional_memory.sql checks for, so
-- re-running that file will not re-add a SET NULL key.

begin;

do $$
declare
  target record;
  existing_name text;
begin
  for target in
    select * from (values
      ('sleep_factor_occurrences', 'session_id', 'chat_sessions',
       'sleep_factor_occurrences_session_id_fkey'),
      ('sleep_factor_occurrences', 'message_id', 'chat_messages',
       'sleep_factor_occurrences_message_fkey'),
      ('sleep_logs', 'session_id', 'chat_sessions',
       'sleep_logs_session_id_fkey')
    ) as t(table_name, column_name, ref_table, constraint_name)
  loop
    for existing_name in
      select c.conname
      from pg_constraint c
      join pg_attribute a
        on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
      where c.contype = 'f'
        and c.conrelid = format('public.%I', target.table_name)::regclass
        and array_length(c.conkey, 1) = 1
        and a.attname = target.column_name
    loop
      execute format('alter table public.%I drop constraint %I',
                     target.table_name, existing_name);
    end loop;

    execute format(
      'alter table public.%I add constraint %I foreign key (%I) '
      'references public.%I (id) on delete cascade',
      target.table_name, target.constraint_name,
      target.column_name, target.ref_table
    );
  end loop;
end
$$;

-- Every writer sets session_id, so a null here means the session was already
-- deleted under the old SET NULL rule. Remove those leftovers.
delete from public.sleep_factor_occurrences where session_id is null;

commit;
