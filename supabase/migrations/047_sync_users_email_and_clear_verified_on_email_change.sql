-- 1) public.users.email was never populated (the app only writes id/profile
--    fields), but the grg_admin promo-code pages read it. Keep it in sync with
--    auth.users.email.
-- 2) A verified flag belongs to an email, not an account: when an account's
--    email changes, drop app_metadata.send_unlocked so the new address has to
--    be verified again with a code. (Apple accounts are verified by their
--    apple identity, not this flag, so they are unaffected.)

-- Fill email when a public.users row is created (the app upserts the row
-- after the auth user already exists).
create or replace function public.users_fill_email()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.email is null then
    select a.email into new.email from auth.users a where a.id = new.id;
  end if;
  return new;
exception when unique_violation then
  return new;
end;
$$;

drop trigger if exists users_fill_email on public.users;
create trigger users_fill_email
  before insert on public.users
  for each row execute function public.users_fill_email();

-- On auth email change: clear the verified flag and mirror the email.
-- Never lets a problem here block the auth update itself.
create or replace function public.auth_email_changed()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.email is distinct from old.email then
    new.raw_app_meta_data :=
      coalesce(new.raw_app_meta_data, '{}'::jsonb) - 'send_unlocked';
    begin
      update public.users set email = new.email where id = new.id;
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists auth_email_changed on auth.users;
create trigger auth_email_changed
  before update of email on auth.users
  for each row execute function public.auth_email_changed();

-- Backfill existing accounts (skips any that would collide on the unique
-- email index rather than failing).
update public.users u
set email = a.email
from auth.users a
where a.id = u.id
  and u.email is null
  and a.email is not null
  and not exists (
    select 1 from public.users o where o.email = a.email and o.id <> u.id
  );
