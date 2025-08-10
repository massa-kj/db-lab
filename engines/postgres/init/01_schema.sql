create table if not exists users (
  id serial primary key,
  name text not null,
  created_at timestamptz not null default now()
);

insert into users (name) values ('alice'), ('bob');

