-- A sleep_factors row is deleted once its last occurrence is gone, including
-- when occurrences go via a session/message cascade.
-- Run after session_delete_cascade.sql.

begin;

create or replace function public.delete_orphaned_sleep_factors()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  delete from public.sleep_factors factor
  where factor.id in (select distinct factor_id from deleted_occurrences)
    and not exists (
      select 1 from public.sleep_factor_occurrences occurrence
      where occurrence.factor_id = factor.id
    );
  return null;
end
$$;

drop trigger if exists sleep_factor_occurrences_delete_orphans
  on public.sleep_factor_occurrences;
create trigger sleep_factor_occurrences_delete_orphans
  after delete on public.sleep_factor_occurrences
  referencing old table as deleted_occurrences
  for each statement execute function public.delete_orphaned_sleep_factors();

delete from public.sleep_factors factor
where not exists (
  select 1 from public.sleep_factor_occurrences occurrence
  where occurrence.factor_id = factor.id
);

commit;
