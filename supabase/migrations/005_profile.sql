-- CardDrop user profile fields
-- Run AFTER 001_schema.sql

alter table users
  add column if not exists first_name  text,
  add column if not exists street      text,
  add column if not exists city        text,
  add column if not exists state       text,
  add column if not exists zip         text,
  add column if not exists country     text;
