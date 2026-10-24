-- Audit trail of what each staff member did on the admin site.
--
-- Append-only and written only by the server (service role). RLS is on with no
-- policies, and a trigger refuses UPDATE and DELETE (even for the service role),
-- so a row can't be changed or removed afterwards. staff_id has no foreign key
-- and the email is stored too, so a row stays readable after the staff member is
-- removed. staff_id is null for the temporary shared-password sign-in.

create table if not exists zz_admin_action_log (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  staff_id    uuid,
  staff_email text not null,
  action      text not null,
  target_type text,
  target_id   text,
  detail      jsonb
);

create index if not exists zz_admin_action_log_created_idx on zz_admin_action_log (created_at desc);
create index if not exists zz_admin_action_log_staff_idx on zz_admin_action_log (staff_email, created_at desc);

alter table zz_admin_action_log enable row level security;
revoke all on zz_admin_action_log from anon, authenticated;

create or replace function zz_admin_action_log_append_only() returns trigger
language plpgsql as $$
begin
  raise exception 'zz_admin_action_log is append-only';
end;
$$;

drop trigger if exists zz_admin_action_log_no_change on zz_admin_action_log;
create trigger zz_admin_action_log_no_change
  before update or delete on zz_admin_action_log
  for each row execute function zz_admin_action_log_append_only();
