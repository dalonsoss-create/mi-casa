-- Mi Casa: esquema inicial, pendiente de ejecutar y probar en Supabase.
-- No contiene datos familiares ni credenciales. Ejecutar una vez en un proyecto de prueba.
begin;
create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  household_type text not null default 'family',
  created_at timestamptz not null default now()
);
create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  role text not null check (role in ('admin','member','cleaner')),
  primary key(household_id,user_id)
);
create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  requested_by uuid not null,
  name text not null check(char_length(name) between 1 and 200),
  category text not null check(category in ('Alimentación','Limpieza','Higiene','Mascotas','Otros')),
  quantity numeric not null default 1 check(quantity > 0 and quantity <= 999),
  urgent boolean not null default false,
  purchased boolean not null default false,
  created_at timestamptz not null default now(),
  foreign key(household_id,requested_by) references public.household_members(household_id,user_id)
);
create table public.meal_responses (
  household_id uuid not null,
  user_id uuid not null,
  day date not null,
  lunch text not null default 'pending' check(lunch in ('yes','no','pending')),
  dinner text not null default 'pending' check(dinner in ('yes','no','pending')),
  primary key(household_id,user_id,day),
  foreign key(household_id,user_id) references public.household_members(household_id,user_id) on delete cascade
);
create table public.stay_overrides (
  household_id uuid not null,
  user_id uuid not null,
  day date not null,
  place text not null check(place in ('home','other_home','away','pending')),
  primary key(household_id,user_id,day),
  foreign key(household_id,user_id) references public.household_members(household_id,user_id) on delete cascade
);
create table public.stay_rules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  user_id uuid not null,
  starts_on date not null,
  weekdays smallint[] not null check(cardinality(weekdays) between 1 and 7 and weekdays <@ array[0,1,2,3,4,5,6]::smallint[]),
  every_weeks smallint not null check(every_weeks in (1,2)),
  place text not null check(place in ('home','other_home','away')),
  foreign key(household_id,user_id) references public.household_members(household_id,user_id) on delete cascade
);
create table public.recurring_products (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null check(char_length(name) between 1 and 200),
  quantity numeric not null default 1 check(quantity > 0 and quantity <= 999),
  interval_days integer not null check(interval_days between 1 and 365),
  last_purchased date
);
-- Helper reads membership without triggering recursive RLS.
create function public.my_household_role(h uuid) returns text
language sql stable security definer set search_path = ''
as $$ select role from public.household_members where household_id=h and user_id=(select auth.uid()) $$;
revoke all on function public.my_household_role(uuid) from public, anon, authenticated;
grant execute on function public.my_household_role(uuid) to authenticated;
-- Create a new household and its first admin atomically. Existing households cannot be joined with this function.
create function public.create_household(h_name text, member_name text, h_type text default 'family') returns uuid
language plpgsql security definer set search_path = ''
as $$
declare h uuid; u uuid := auth.uid();
begin
  if u is null then raise exception 'Authentication required'; end if;
  insert into public.households(name, household_type) values(h_name,h_type) returning id into h;
  insert into public.household_members(household_id,user_id,display_name,role) values(h,u,member_name,'admin');
  return h;
end;
$$;
revoke all on function public.create_household(text,text,text) from public, anon, authenticated;
grant execute on function public.create_household(text,text,text) to authenticated;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.shopping_items enable row level security;
alter table public.meal_responses enable row level security;
alter table public.stay_overrides enable row level security;
alter table public.stay_rules enable row level security;
alter table public.recurring_products enable row level security;
revoke all on public.households,public.household_members,public.shopping_items,public.meal_responses,public.stay_overrides,public.stay_rules,public.recurring_products from anon, authenticated;
grant select on public.households,public.household_members to authenticated;
grant update(name,household_type) on public.households to authenticated;
grant select,insert,update,delete on public.shopping_items,public.meal_responses,public.stay_overrides,public.stay_rules,public.recurring_products to authenticated;
create policy household_read on public.households for select to authenticated using(public.my_household_role(id) is not null);
create policy household_admin_update on public.households for update to authenticated using(public.my_household_role(id)='admin') with check(public.my_household_role(id)='admin');
create policy membership_read on public.household_members for select to authenticated using(user_id=(select auth.uid()) or public.my_household_role(household_id)='admin');
-- Membership changes are NOT allowed by the client. Add an audited invitation flow before pilot.
create policy shopping_read on public.shopping_items for select to authenticated using(
  public.my_household_role(household_id)='admin' or
  (public.my_household_role(household_id)='member' and not purchased) or
  (public.my_household_role(household_id)='cleaner' and not purchased and category in ('Limpieza','Higiene'))
);
create policy shopping_request on public.shopping_items for insert to authenticated with check(
  requested_by=(select auth.uid()) and not purchased and
  (public.my_household_role(household_id) in ('admin','member') or
   (public.my_household_role(household_id)='cleaner' and category in ('Limpieza','Higiene')))
);
create policy shopping_admin_update on public.shopping_items for update to authenticated using(public.my_household_role(household_id)='admin') with check(public.my_household_role(household_id)='admin');
create policy shopping_admin_delete on public.shopping_items for delete to authenticated using(public.my_household_role(household_id)='admin');
create policy meals_read on public.meal_responses for select to authenticated using(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid())));
create policy meals_insert on public.meal_responses for insert to authenticated with check(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid())));
create policy meals_update on public.meal_responses for update to authenticated using(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid()))) with check(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid())));
create policy meals_delete on public.meal_responses for delete to authenticated using(public.my_household_role(household_id)='admin');
create policy stays_read on public.stay_overrides for select to authenticated using(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid())));
create policy stays_insert on public.stay_overrides for insert to authenticated with check(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid())));
create policy stays_update on public.stay_overrides for update to authenticated using(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid()))) with check(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid())));
create policy stays_delete on public.stay_overrides for delete to authenticated using(public.my_household_role(household_id)='admin');
create policy rules_read on public.stay_rules for select to authenticated using(public.my_household_role(household_id)='admin' or (public.my_household_role(household_id)='member' and user_id=(select auth.uid())));
create policy rules_admin on public.stay_rules for all to authenticated using(public.my_household_role(household_id)='admin') with check(public.my_household_role(household_id)='admin');
create policy recurring_admin on public.recurring_products for all to authenticated using(public.my_household_role(household_id)='admin') with check(public.my_household_role(household_id)='admin');
commit;
