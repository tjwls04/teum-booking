-- Use a development database. The fixture data and failure trigger roll back.
begin;
set local time zone 'UTC';

insert into auth.users (id,email,email_confirmed_at) values
  ('f5000000-0000-4000-8000-000000000001','r5-a@example.invalid',now()),
  ('f5000000-0000-4000-8000-000000000002','r5-b@example.invalid',now());
insert into public.shops (id,owner_user_id,slug,name,min_notice_minutes,booking_window_days,cancellation_policy,deposit_policy) values
  ('f5000000-0000-4000-8000-000000000011','f5000000-0000-4000-8000-000000000001','r5-test-a','Fixture A',0,
    case when to_regprocedure('public.r9_allow_booking(text,text,text,text)') is null then 200 else 90 end,'Fixture cancellation','Fixture deposit'),
  ('f5000000-0000-4000-8000-000000000012','f5000000-0000-4000-8000-000000000002','r5-test-b','Fixture B',0,60,'','');
insert into public.services (id,shop_id,name,duration_minutes,buffer_minutes,price_krw,deposit_krw,is_public) values
  ('f5000000-0000-4000-8000-000000000021','f5000000-0000-4000-8000-000000000011','Public basic',30,15,15000,0,true),
  ('f5000000-0000-4000-8000-000000000022','f5000000-0000-4000-8000-000000000011','Public deposit',30,15,21000,5000,true),
  ('f5000000-0000-4000-8000-000000000023','f5000000-0000-4000-8000-000000000012','Other shop',30,15,10000,0,true),
  ('f5000000-0000-4000-8000-000000000024','f5000000-0000-4000-8000-000000000011','Internal only',30,15,10000,0,false);
insert into public.shop_bank_accounts values ('f5000000-0000-4000-8000-000000000011','Fixture bank','123456','Fixture holder');
insert into public.shop_weekly_periods
select shop, weekday, kind, starts, ends
from (values ('f5000000-0000-4000-8000-000000000011'::uuid), ('f5000000-0000-4000-8000-000000000012'::uuid)) shops(shop)
cross join generate_series(1,7) weekday
cross join (values ('opening',540,1080), ('break',720,780)) times(kind,starts,ends);
delete from public.shop_weekly_periods
where shop_id = 'f5000000-0000-4000-8000-000000000011'
  and iso_weekday = extract(isodow from (now() at time zone 'Asia/Seoul')::date + 3);

insert into public.blocks (id,shop_id,starts_at,ends_at)
select 'f5000000-0000-4000-8000-000000000041', 'f5000000-0000-4000-8000-000000000011', t, t + interval '15 min'
from (select (((now() at time zone 'Asia/Seoul')::date + 1) + time '10:30') at time zone 'Asia/Seoul' as t) fixture;
insert into public.occupied_slots (shop_id,slot_start,block_id)
select shop_id,starts_at,id from public.blocks where id = 'f5000000-0000-4000-8000-000000000041';

create function pg_temp.r5_force_failure()
returns trigger language plpgsql as $$
begin
  if new.event_key = 'f5000000-0000-4000-8000-000000000055' then
    raise exception using errcode = 'P0001', message = 'forced_event_failure';
  end if;
  return new;
end;
$$;
create trigger r5_verify_failure before insert on public.booking_events for each row execute function pg_temp.r5_force_failure();

do $$
declare
  endpoint text;
begin
  foreach endpoint in array array[
    'public.r5_allow_request(text,text,text)', 'public.r5_catalog(text)', 'public.r5_slots(text,uuid,date,integer,integer)',
    'public.r5_create(text,uuid,timestamptz,integer,integer,text,text,text,uuid,text)', 'public.r5_confirmation(text,boolean)'
  ] loop
    if has_function_privilege('anon',endpoint,'EXECUTE') or has_function_privilege('authenticated',endpoint,'EXECUTE')
      or not has_function_privilege('service_role',endpoint,'EXECUTE')
      or not exists (select from pg_proc where oid = endpoint::regprocedure and prosecdef and 'search_path=""' = any(proconfig))
    then raise exception 'RPC privilege/search_path mismatch'; end if;
  end loop;
  if has_table_privilege('authenticated','public.bookings','INSERT')
    or has_table_privilege('service_role','public.occupied_slots','INSERT')
    or has_schema_privilege('service_role','r5_private','USAGE')
  then raise exception 'Direct access changed'; end if;
end;
$$;

set local role service_role;
do $$
declare
  a constant uuid := 'f5000000-0000-4000-8000-000000000011';
  basic constant uuid := 'f5000000-0000-4000-8000-000000000021';
  with_deposit constant uuid := 'f5000000-0000-4000-8000-000000000022';
  other constant uuid := 'f5000000-0000-4000-8000-000000000023';
  d date := (now() at time zone 'Asia/Seoul')::date + 1;
  anchor timestamptz := d::timestamp at time zone 'Asia/Seoul';
  slots jsonb;
  res jsonb;
  created_booking_id uuid;
  test_case record;
begin
  res := public.r5_catalog('r5-test-a');
  if jsonb_array_length(res->'services') <> 2 or res::text ~ 'Internal only|Fixture bank|123456|owner_user_id'
    or (res->>'lastDay')::date <> d + 88 then raise exception 'Catalog visibility/window failed'; end if;
  slots := public.r5_slots('r5-test-a', basic, d, 1, 1);
  if not slots @> jsonb_build_array(anchor + interval '9h', anchor + interval '11h 15min')
    or slots @> jsonb_build_array(anchor + interval '10h')
    or slots @> jsonb_build_array(anchor + interval '11h 30min') then
    raise exception 'Blocked time or break/preparation boundary failed';
  end if;
  if public.r5_slots('r5-test-a', basic, d + 2, 1, 1) <> '[]'::jsonb then
    raise exception 'Closed day has available slots';
  end if;

  for test_case in select * from (values
      (other, anchor + interval '9h', 1,1,'r5_revision'),
      (basic, anchor + interval '9h', 2,1,'r5_revision'),
      (basic, anchor + interval '9h', 1,2,'r5_revision'),
      (basic, anchor + interval '9h 1min', 1,1,'r5_time'),
      (basic, anchor + interval '10h', 1,1,'r5_time'),
      (basic, anchor + interval '11h 30min', 1,1,'r5_time'),
      (basic, anchor + interval '12h', 1,1,'r5_time'),
      (basic, anchor + interval '2d 9h', 1,1,'r5_time'),
      (basic, anchor - interval '4d', 1,1,'r5_time'),
      (basic, anchor + interval '95d 9h', 1,1,'r5_time')
    ) cases(svc,start_at,revision,policy,expected)
  loop
    begin
      perform public.r5_create('r5-test-a', test_case.svc, test_case.start_at, test_case.revision, test_case.policy,
        'Fixture guest', '010-0000-0000', 'r5-privacy-v1', gen_random_uuid(), repeat('a',64));
      raise exception 'Invalid reservation accepted';
    exception when sqlstate 'PT409' then
      if sqlerrm <> test_case.expected then raise; end if;
    end;
  end loop;

  res := public.r5_create('r5-test-a', basic, anchor + interval '9h', 1, 1,
    'Fixture guest', '010-0000-0000', 'r5-privacy-v1', 'f5000000-0000-4000-8000-000000000051', '51' || repeat('1',62));
  if res <> '{"created":true}'::jsonb then raise exception 'Expected reservation creation'; end if;

  select id into created_booking_id from public.bookings where shop_id = a and confirmation_token_hash = decode('51' || repeat('1',62),'hex');
  if (select count(*) from public.occupied_slots where occupied_slots.booking_id =
      (select id from public.bookings where confirmation_token_hash = decode('51' || repeat('1',62),'hex'))) <> 3
    or not exists (select from public.bookings where id = created_booking_id and status = 'confirmed' and price_krw = 15000)
  then raise exception 'Booking snapshot or full slot count incorrect'; end if;

  res := public.r5_create('r5-test-a', basic, anchor + interval '9h', 1, 1,
    'Fixture guest', '01000000000', 'r5-privacy-v1', 'f5000000-0000-4000-8000-000000000051', '51' || repeat('1',62));
  if res <> '{"created":false}'::jsonb then raise exception 'Expected idempotent replay'; end if;

  begin
    perform public.r5_create('r5-test-a', basic, anchor + interval '9h', 1, 1,
      'Changed name', '01000000000', 'r5-privacy-v1', 'f5000000-0000-4000-8000-000000000051', '51' || repeat('1',62));
    raise exception 'Changed idempotent request accepted';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r5_key' then raise; end if;
  end;
  if public.r5_confirmation('51' || repeat('9',62),false) is not null then raise exception 'Unknown token exposed booking'; end if;
  res := public.r5_confirmation('51' || repeat('1',62),false);
  if res->>'status' <> 'confirmed' or res ? 'customer_name' or res ? 'shop_id'
    or res::text ~ 'Fixture guest|01000000000|123456' then raise exception 'Confirmation leaked data'; end if;

  begin
    perform public.r5_create('r5-test-a', basic, anchor + interval '16h', 1, 1,
      'Fixture guest', '01000000000', 'r5-privacy-v1', 'f5000000-0000-4000-8000-000000000055', '51' || repeat('5',62));
    raise exception 'Failure trigger did not run';
  exception when raise_exception then
    if sqlerrm <> 'forced_event_failure' then raise; end if;
  end;
  if exists (select from public.bookings where idempotency_key = 'f5000000-0000-4000-8000-000000000055')
    or exists (select from public.occupied_slots where shop_id = a and slot_start = anchor + interval '16h')
  then raise exception 'Write not rolled back'; end if;

  perform public.r5_create('r5-test-b', other, anchor + interval '9h', 1, 1,
    'Fixture guest', '01000000000', 'r5-privacy-v1', gen_random_uuid(), '51' || repeat('3',62));
  perform public.r5_create('r5-test-a', with_deposit, anchor + interval '14h', 1, 1,
    'Fixture guest', '01000000000', 'r5-privacy-v1', gen_random_uuid(), '51' || repeat('2',62));
  perform public.r5_create('r5-test-a', with_deposit, anchor + interval '15h', 1, 1,
    'Fixture guest', '01000000000', 'r5-privacy-v1', gen_random_uuid(), '51' || repeat('4',62));
  res := public.r5_confirmation('51' || repeat('2',62), false);
  if res->>'status' <> 'pending_deposit' or res#>>'{account,number}' is distinct from '123456' then
    raise exception 'Payment instructions not scoped to pending token';
  end if;
  res := public.r5_confirmation('51' || repeat('4',62), true);
  if res->>'depositStatus' <> 'reported' or res->>'status' <> 'pending_deposit' then
    raise exception 'Early report did not preserve pending state';
  end if;
  for attempt in 1..6 loop
    if not public.r5_allow_request('create','r5-test-a',repeat('a',64)) then
      raise exception 'Client blocked before limit';
    end if;
  end loop;
  if public.r5_allow_request('create','r5-test-a',repeat('a',64))
    or not public.r5_allow_request('create','r5-test-a',repeat('b',64)) then
    raise exception 'Client limit did not isolate address buckets';
  end if;
end;
$$;
reset role;

update public.bookings set created_at = now() - interval '2h', deposit_due_at = now()
where confirmation_token_hash in (decode('51' || repeat('2',62),'hex'),decode('51' || repeat('4',62),'hex'));
update public.shops set slug = 'r5-test-a-renamed', policy_revision = 2
where id = 'f5000000-0000-4000-8000-000000000011';

set local role service_role;
do $$
declare
  d date := (now() at time zone 'Asia/Seoul')::date + 1;
  anchor timestamptz := d::timestamp at time zone 'Asia/Seoul';
  res jsonb;
begin
  res := public.r5_create('r5-test-a', 'f5000000-0000-4000-8000-000000000021', anchor + interval '9h', 1, 1,
    'Fixture guest', '01000000000', 'r5-privacy-v1', 'f5000000-0000-4000-8000-000000000051', '51' || repeat('1',62));
  if res <> '{"created":false}'::jsonb then raise exception 'Retry with stale policy/renamed slug failed'; end if;

  perform public.r5_create('r5-test-a-renamed', 'f5000000-0000-4000-8000-000000000021', anchor + interval '14h', 1, 2,
    'Fixture guest', '01000000000', 'r5-privacy-v1', gen_random_uuid(), '51' || repeat('6',62));
  res := public.r5_confirmation('51' || repeat('2',62),true);
  if res->>'status' <> 'expired' or res->>'followup' <> 'review_needed' or res->'account' <> 'null'::jsonb then
    raise exception 'Late report altered the schedule or returned bank details';
  end if;
  res := public.r5_confirmation('51' || repeat('4',62),false);
  if res->>'depositStatus' <> 'reported' or res->>'status' <> 'pending_deposit' then
    raise exception 'Reported booking was expired';
  end if;
  if (select count(*) from public.occupied_slots s join public.bookings b on b.id = s.booking_id
      where b.confirmation_token_hash = decode('51' || repeat('6',62),'hex')) <> 3 then
    raise exception 'Late report released the new reservation';
  end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f5000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f5000000-0000-4000-8000-000000000011';
  request_id uuid := gen_random_uuid();
  service_id uuid;
begin
  service_id := public.r5_create_service(a,request_id,'New service','',30,15,15000,0,'private');
  if public.r5_create_service(a,request_id,'New service','',30,15,15000,0,'private') is distinct from service_id
    or (select count(*) from public.services where name = 'New service') <> 1 then
    raise exception 'Service submit replay created a duplicate';
  end if;
  begin
    perform public.r5_create_service('f5000000-0000-4000-8000-000000000012',request_id,'New service','',30,15,15000,0,'private');
    raise exception 'Other shop service was added';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

rollback;
select 'R5 customer booking checks passed' as result;
