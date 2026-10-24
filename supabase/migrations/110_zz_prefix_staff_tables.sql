-- Staff tables get the zz_ prefix (standing reference data, see 029).
-- Migration 109 created them without it. Indexes, constraints and the
-- invited_by foreign key follow the rename automatically.
alter table internal_users rename to zz_internal_users;
alter table admin_role_permissions rename to zz_admin_role_permissions;
alter index internal_users_email_idx rename to zz_internal_users_email_idx;
