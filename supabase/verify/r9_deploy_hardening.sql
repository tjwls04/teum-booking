-- Run after R9 on an isolated development/test database. Fixtures roll back.
begin;

insert into auth.users(id,email,email_confirmed_at) values
  ('f9000000-0000-4000-8000-000000000001','r9-owner-a@example.invalid',now()),
  ('f9000000-0000-4000-8000-000000000002','r9-owner-b@example.invalid',now());
insert into public.shops(id,owner_user_id,slug,name,min_notice_minutes) values
  ('f9000000-0000-4000-8000-000000000011','f9000000-0000-4000-8000-000000000001','r9-test-a','Fixture A',0),
  ('f9000000-0000-4000-8000-000000000012','f9000000-0000-4000-8000-000000000002','r9-test-b','Fixture B',0);
insert into public.shop_weekly_periods
select id,d,'opening',540,1080 from public.shops cross join generate_series(1,7) d where slug = 'r9-test-a';

do $$
begin
  if has_function_privilege('anon','public.r9_allow_booking(text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated','public.r9_allow_booking(text,text,text,text)','EXECUTE')
    or not has_function_privilege('service_role','public.r9_allow_booking(text,text,text,text)','EXECUTE')
    or has_function_privilege('authenticated','r4_private.r4_save_service(uuid,uuid,integer,text,text,integer,integer,integer,integer,text)','EXECUTE')
    or has_schema_privilege('service_role','r9_private','USAGE')
    or not exists (select from pg_constraint where conrelid = 'public.shops'::regclass and conname = 'shops_booking_window_public_cap')
  then raise exception 'Unexpected R9 privilege or cap'; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f9000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f9000000-0000-4000-8000-000000000011';
  key constant uuid := 'f9000000-0000-4000-8000-000000000021';
  svc uuid;
begin
  begin
    perform public.r4_save_policy(a,1,0,91,0,60,'','','','','');
    raise exception 'Window above the public cap was accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'r4_policy_input' then raise; end if;
  end;
  perform public.r4_save_policy(a,1,0,90,0,60,'','','','','');
  if not exists (select from public.shops where id = a and booking_window_days = 90 and policy_revision = 2) then
    raise exception 'The window boundary was not persisted';
  end if;
  begin
    perform public.r4_save_service(a,null,null,'Fixture service','',30,0,10000,0,'public');
    raise exception 'Legacy create bypassed the request ledger';
  exception when invalid_parameter_value then
    if sqlerrm <> 'r9_service_request_required' then raise; end if;
  end;
  svc := public.r5_create_service(a,key,'Fixture service','',30,0,10000,0,'public');
  if public.r5_create_service(a,key,'Fixture service','',30,0,10000,0,'public') <> svc then
    raise exception 'Service replay returned another row';
  end if;
  begin
    perform public.r5_create_service(a,key,'Changed during retry','',30,0,10000,0,'public');
    raise exception 'Changed replay was accepted';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r5_service_key' then raise; end if;
  end;
  perform set_config('r9.fixture.service',svc::text,true);
end;
$$;
reset role;

set local role service_role;
do $$
declare
  token constant text := repeat('a',64);
  same_client constant text := repeat('b',64);
  other_client constant text := repeat('e',64);
  svc uuid := current_setting('r9.fixture.service')::uuid;
  anchor timestamptz := (((now() at time zone 'Asia/Seoul')::date+1)+time '10:00') at time zone 'Asia/Seoul';
begin
  if public.r9_allow_booking('catalog','r9-test-missing',same_client,null) <> 'missing'
    or public.r9_allow_booking('confirm',null,same_client,token) <> 'missing'
    or public.r9_allow_booking('report',null,same_client,token) <> 'missing'
  then raise exception 'Unknown shop or token was admitted'; end if;
  for attempt in 1..6 loop
    if public.r9_allow_booking('create','r9-test-a',same_client,token) <> 'allowed' then raise exception 'Limited too soon'; end if;
  end loop;
  for attempt in 1..35 loop
    if public.r9_allow_booking('create','r9-test-a',same_client,token) <> 'limited' then raise exception 'Client limit bypassed'; end if;
  end loop;
  if public.r9_allow_booking('create','r9-test-a',other_client,token) <> 'allowed' then
    raise exception 'Rejected traffic debited another client''s shop capacity';
  end if;
  perform public.r5_create('r9-test-a',svc,anchor,1,2,'Fixture guest','01000000000','r5-privacy-v1',
    'f9000000-0000-4000-8000-000000000031',token);
  for attempt in 1..12 loop
    -- The missing-token report above debited same_client, so use another address here.
    if public.r9_allow_booking('report',null,other_client,token) <> 'allowed' then raise exception 'Report limit triggered too soon'; end if;
  end loop;
  if public.r9_allow_booking('report',null,other_client,token) <> 'limited'
    or public.r9_allow_booking('confirm',null,other_client,token) <> 'allowed'
    or public.r9_allow_booking('create','r9-test-b',other_client,repeat('f',64)) <> 'allowed'
  then raise exception 'Report attempts affected independent operations or shops'; end if;
end;
$$;
reset role;
update public.shops set slug = 'r9-test-a-renamed'
where id = 'f9000000-0000-4000-8000-000000000011';
set local role service_role;
do $$
declare
  token constant text := repeat('a',64);
  svc uuid := current_setting('r9.fixture.service')::uuid;
  anchor timestamptz := (((now() at time zone 'Asia/Seoul')::date+1)+time '10:00') at time zone 'Asia/Seoul';
begin
  if public.r9_allow_booking('create','r9-test-a',null,token) <> 'allowed'
    or public.r5_create('r9-test-a',svc,anchor,1,2,'Fixture guest','01000000000','r5-privacy-v1',
    'f9000000-0000-4000-8000-000000000031',token) <> '{"created":false}'
  then raise exception 'Slug change prevented original booking recovery'; end if;
end;
$$;
reset role;

do $$
begin
  if (select used from r9_private.shop_quota where shop_id = 'f9000000-0000-4000-8000-000000000011' and operation = 1) <> 8
    or exists (select from r9_private.shop_quota where operation = 0) then
    raise exception 'Unknown target or rejected client debited shared quota';
  end if;
end;
$$;

rollback;
select 'R9 deployment hardening checks passed' as result;
