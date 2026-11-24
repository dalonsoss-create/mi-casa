begin;
create schema casa_private;
revoke all on schema casa_private from public, anon, authenticated;
create table casa_private.homes (
  id uuid primary key default gen_random_uuid(),
  revision bigint not null default 0,
  data jsonb not null check (jsonb_typeof(data)='object')
);
-- Slots identify the six fictitious profiles from version 0.3.
create table casa_private.members (
  account uuid primary key references auth.users(id) on delete cascade,
  home uuid not null references casa_private.homes(id) on delete cascade,
  slot integer not null check (slot between 0 and 5),
  unique(home, slot)
);
alter table casa_private.homes enable row level security;
alter table casa_private.members enable row level security;
revoke all on all tables in schema casa_private from public, anon, authenticated;

-- Neither the household nor the identity is supplied by the browser.
create function public.casa_read() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  m casa_private.members; h casa_private.homes; visible jsonb; basket jsonb;
  answers jsonb; stays jsonb; routines jsonb; totals jsonb;
  names text[] := array['Alex','Luz','Sam','Mar','Sol','Paz'];
begin
  select * into strict m from casa_private.members where account=auth.uid();
  select * into strict h from casa_private.homes where id=m.home;
  if m.slot < 2 then visible := h.data;
  else
    select coalesce(jsonb_agg(jsonb_build_object('n',i->'n','q',i->'q','urgent',i->'urgent','cat',i->'cat',
      'done',false,'p','[null,null,null,null]'::jsonb)), '[]') into basket
    from jsonb_array_elements(h.data->'items') i where not (i->>'done')::boolean
      and (m.slot < 5 or i->>'cat' in ('Limpieza','Higiene'));
    visible := jsonb_build_object('items',basket);
    if m.slot < 5 then
      select coalesce(jsonb_object_agg(key,value->m.slot),'{}') into answers from jsonb_each(h.data->'meals');
      select coalesce(jsonb_object_agg(key,value->m.slot),'{}') into stays from jsonb_each(h.data->'locations');
      select coalesce(jsonb_agg(r),'[]') into routines from jsonb_array_elements(h.data->'rules') r where r->>'person'=names[m.slot+1];
      select coalesce(jsonb_object_agg(key,(select jsonb_build_array(
        count(*) filter(where row->>0='Sí'),count(*) filter(where row->>0='?'),
        count(*) filter(where row->>1='Sí'),count(*) filter(where row->>1='?'))
        from jsonb_array_elements(value) as a(row))), '{}') into totals from jsonb_each(h.data->'meals');
      visible := visible || jsonb_build_object('answers',answers,'stays',stays,'rules',routines,'totals',totals);
    end if;
  end if;
  return jsonb_build_object('revision',h.revision,'slot',m.slot,'data',visible);
end $$;

create function public.casa_write(expected bigint, action text, payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  m casa_private.members; h casa_private.homes; doc jsonb; d text:=payload->>'day';
  v text:=payload->>'value'; j int; cat text; product text; pos int; item jsonb;
  names text[] := array['Alex','Luz','Sam','Mar','Sol','Paz'];
begin
  select * into strict m from casa_private.members where account=auth.uid();
  select * into strict h from casa_private.homes where id=m.home for update;
  if expected is distinct from h.revision then raise exception 'revision_conflict'; end if;
  doc:=h.data;
  if action='admin' and m.slot < 2 then doc:=payload;
  elsif action in ('meal','stay') and m.slot between 2 and 4 then
    if d is null or d !~ '^\d{4}-\d{2}-\d{2}$' or d::date::text<>d then raise exception 'invalid_date'; end if;
    if action='meal' and v in ('Sí','No','?') and payload->>'index' in ('0','1') then
      j:=(payload->>'index')::int;
      if not ((doc->'meals') ? d) then doc:=jsonb_set(doc,array['meals',d],'[["?","?"],["?","?"],["?","?"],["?","?"],["?","?"]]'); end if;
      doc:=jsonb_set(doc,array['meals',d,m.slot::text,j::text],to_jsonb(v));
    elsif action='stay' and v in ('manual?','En esta casa','En casa de papá','Fuera / viaje') then
      if not ((doc->'locations') ? d) then doc:=jsonb_set(doc,array['locations',d],'["?","?","?","?","?"]'); end if;
      doc:=jsonb_set(doc,array['locations',d,m.slot::text],to_jsonb(v));
    else raise exception 'invalid_response'; end if;
  elsif action='add' then
    product:=btrim(payload->>'n'); cat:=payload->>'cat';
    if product is null or length(product) not between 1 and 100 or cat is null or cat not in ('Alimentación','Limpieza','Mascotas','Higiene','Otros')
      or (m.slot=5 and cat not in ('Limpieza','Higiene')) then raise exception 'invalid_product'; end if;
    select (ord-1)::int,i into pos,item from jsonb_array_elements(doc->'items') with ordinality as t(i,ord)
      where lower(i->>'n')=lower(product) and (m.slot<>5 or i->>'cat' in ('Limpieza','Higiene')) limit 1;
    item:=coalesce(item,jsonb_build_object('n',product,'q',1,'p','[null,null,null,null]'::jsonb))
      ||jsonb_build_object('cat',cat,'done',false,'by',names[m.slot+1],'urgent',coalesce((item->>'urgent')::boolean,false) or payload->'urgent'='true'::jsonb);
    if pos is null then doc:=jsonb_set(doc,'{items}',(doc->'items')||jsonb_build_array(item));
    else doc:=jsonb_set(doc,array['items',pos::text],item); end if;
  else raise exception 'forbidden'; end if;
  update casa_private.homes set data=doc, revision=revision+1 where id=h.id;
  return public.casa_read();
end $$;
revoke all on function public.casa_read(), public.casa_write(bigint,text,jsonb) from public,anon;
grant execute on function public.casa_read(), public.casa_write(bigint,text,jsonb) to authenticated;
commit;
