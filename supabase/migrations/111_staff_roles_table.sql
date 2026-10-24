-- A staff member can hold several roles. Roles become a table, and who has which
-- role moves out of zz_internal_users.role into a join table.
--   zz_admin_roles           the roles that exist
--   zz_admin_role_permissions (existing) role must now exist in zz_admin_roles
--   zz_internal_user_roles   one row per person per role
-- A person's permissions are the union of their roles' permissions.

create table if not exists zz_admin_roles (
  role        text primary key,
  description text not null
);

insert into zz_admin_roles (role, description) values
  ('manager', 'Everything, including staff management'),
  ('compliance', 'Reported cards, appeals, suspended accounts, legal holds, held-card pictures'),
  ('marketing', 'Add and Manage Marketing Cards'),
  ('finance', 'Promo codes')
on conflict do nothing;

alter table zz_admin_roles enable row level security;
revoke all on zz_admin_roles from anon, authenticated;

-- The hard-coded role list on the permissions table becomes a link to zz_admin_roles.
alter table zz_admin_role_permissions drop constraint if exists admin_role_permissions_role_check;
alter table zz_admin_role_permissions
  add constraint zz_admin_role_permissions_role_fkey foreign key (role) references zz_admin_roles (role);

create table if not exists zz_internal_user_roles (
  auth_user_id uuid not null references zz_internal_users (auth_user_id) on delete cascade,
  role         text not null references zz_admin_roles (role),
  primary key (auth_user_id, role)
);

alter table zz_internal_user_roles enable row level security;
revoke all on zz_internal_user_roles from anon, authenticated;

-- Carry over everyone's current role BEFORE the column goes.
insert into zz_internal_user_roles (auth_user_id, role)
select auth_user_id, role from zz_internal_users
on conflict do nothing;

alter table zz_internal_users drop column role;
