-- Run once after migration. The pilot contains two independent test homes.
insert into casa_private.homes (id,data)
select id::uuid, jsonb_build_object(
  'items','[]'::jsonb,'fees','[{"fee":8.2,"min":60,"free":null},{"fee":8,"min":0,"free":100},{"fee":7,"min":0,"free":null},{"fee":7,"min":0,"free":100}]'::jsonb,
  'meals','{}'::jsonb,'locations','{}'::jsonb,'rules','[]'::jsonb,'stock','[]'::jsonb,
  'settings',jsonb_build_object('name',label,'type','Piso compartido','ask','09:30','summary','11:00'))
from (values ('00000000-0000-4000-8000-000000000001','Hogar Nube'),
             ('00000000-0000-4000-8000-000000000002','Hogar Brisa')) fixtures(id,label)
on conflict(id) do nothing;
-- Provisioning is restricted to the project owner in SQL Editor.
-- Map an Auth test account's UUID to one home and slot (0–1 admin,
-- 2–4 participant, 5 cleaning). No browser client can create memberships.
-- insert into casa_private.members(account,home,slot) values
-- ('<auth-user-uuid>','00000000-0000-4000-8000-000000000001',2);
