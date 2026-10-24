-- "Show all cards" on Add Marketing Cards needs no fresh authenticator code for
-- roles that have marketing.all_cards (manager). Everyone else with
-- marketing.curate (the marketing role) must enter a fresh code, which then lasts
-- admin_marketing_all_unlock_minutes (and ends on idle / leaving the marketing pages).
insert into zz_admin_role_permissions (role, permission) values ('manager', 'marketing.all_cards')
on conflict do nothing;
