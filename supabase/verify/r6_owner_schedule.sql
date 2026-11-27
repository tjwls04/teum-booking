-- Run on a development database after R2–R6. All fixtures and the failure trigger roll back.
begin;
set local time zone 'UTC';

insert into auth.users(id,email,email_confirmed_at) values
  ('f6000000-0000-4000-8000-000000000001','r6-a@example.invalid',now()),
  ('f6000000-0000-4000-8000-000000000002','r6-b@example.invalid',now());
insert into public.shops(id,owner_user_id,slug,name,min_notice_minutes,cancellation_policy,deposit_policy) values
  ('f6000000-0000-4000-8000-000000000011','f6000000-0000-4000-8000-000000000001','r6-test-a','Fixture A',120,'Fixture cancel','Fixture deposit'),
  ('f6000000-0000-4000-8000-000000000012','f6000000-0000-4000-8000-000000000002','r6-test-b','Fixture B',0,'','');
insert into public.services(id,shop_id,name,duration_minutes,buffer_minutes,price_krw,deposit_krw,is_public) values
  ('f6000000-0000-4000-8000-000000000021','f6000000-0000-4000-8000-000000000011','Fixture service',30,15,15000,0,true),
  ('f6000000-0000-4000-8000-000000000022','f6000000-0000-4000-8000-000000000011','Fixture deposit service',30,15,25000,5000,true),
  ('f6000000-0000-4000-8000-000000000023','f6000000-0000-4000-8000-000000000012','Fixture other service',30,15,10000,0,true);
insert into public.shop_bank_accounts values ('f6000000-0000-4000-8000-000000000011','Fixture bank','123456','Fixture holder');
insert into public.shop_weekly_periods
select s.id, d, 'opening', 540, 1080 from public.shops s cross join generate_series(1,7) d where s.slug in ('r6-test-a','r6-test-b');

create function pg_temp.r6_force_event_failure()
returns trigger language plpgsql as $$
begin
  if new.event_key = 'f6000000-0000-4000-8000-000000000068' then
    raise exception 'forced_r6_event_failure';
  end if;
  return new;
end;
$$;
create trigger verify_r6_failure before insert on public.booking_events
for each row execute function pg_temp.r6_force_event_failure();

do $$
declare endpoint text;
begin
  foreach endpoint in array array[
    'public.r6_manual(uuid,uuid,integer,integer,timestamptz,text,text,text,uuid)',
    'public.r6_change(uuid,uuid,integer,text,timestamptz,text,uuid)',
    'public.r6_block(uuid,uuid,timestamptz,timestamptz,text)',
    'public.r6_unblock(uuid,uuid)','public.r6_schedule(uuid,date,date,text)','public.r6_detail(uuid,uuid)'
  ] loop
    if has_function_privilege('anon',endpoint,'EXECUTE') or has_function_privilege('service_role',endpoint,'EXECUTE')
      or not has_function_privilege('authenticated',endpoint,'EXECUTE')
      or not exists (select from pg_proc where oid = endpoint::regprocedure and prosecdef and 'search_path=""' = any(proconfig))
    then raise exception 'RPC security configuration mismatch'; end if;
  end loop;
  if has_table_privilege('authenticated','public.bookings','INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated','public.occupied_slots','INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated','public.blocks','INSERT,UPDATE,DELETE')
  then raise exception 'Direct table writes available'; end if;
end;
$$;

set local role service_role;
select public.r5_create('r6-test-a','f6000000-0000-4000-8000-000000000021',
  (((now() at time zone 'Asia/Seoul')::date + 1) + time '09:00') at time zone 'Asia/Seoul',
  1, 1, 'Fixture online', '01000000000', 'r5-privacy-v1',
  'f6000000-0000-4000-8000-000000000051', '61' || repeat('a',62));
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f6000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f6000000-0000-4000-8000-000000000011';
  b constant uuid := 'f6000000-0000-4000-8000-000000000012';
  svc constant uuid := 'f6000000-0000-4000-8000-000000000021';
  fee constant uuid := 'f6000000-0000-4000-8000-000000000022';
  d date := (now() at time zone 'Asia/Seoul')::date + 1;
  anchor timestamptz := d::timestamp at time zone 'Asia/Seoul';
  manual_id uuid;
  replacement uuid;
  fee_id uuid;
  created_block_id uuid;
  cancel_key uuid := gen_random_uuid();
  detail jsonb;
  schedule jsonb;
begin
  begin
    perform public.r6_manual(a,svc,1,1,anchor+interval '9h 30min','Fixture name','01000000000','kakao',gen_random_uuid());
    raise exception 'Manual booking overlapped online preparation';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r6_time' then raise; end if;
  end;
  manual_id := public.r6_manual(a,svc,1,1,anchor+interval '10h','Fixture name','01000000000','kakao',
    'f6000000-0000-4000-8000-000000000052');
  if public.r6_manual(a,svc,1,1,anchor+interval '10h','Fixture name','01000000000','kakao',
    'f6000000-0000-4000-8000-000000000052') <> manual_id then
    raise exception 'Manual retry created another booking';
  end if;

  begin
    perform public.r6_block(a,gen_random_uuid(),anchor+interval '10h 30min',anchor+interval '11h','Overlapping');
    raise exception 'Block overlapped booking';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r6_time' then raise; end if;
  end;
  created_block_id := public.r6_block(a,'f6000000-0000-4000-8000-000000000041',anchor+interval '11h',anchor+interval '12h','Fixture block');
  begin
    perform public.r6_change(a,manual_id,1,'move',anchor+interval '11h',null,gen_random_uuid());
    raise exception 'Move onto a block was accepted';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r6_time' then raise; end if;
  end;
  begin
    perform public.r6_change(a,manual_id,1,'move',anchor+interval '12h',null,'f6000000-0000-4000-8000-000000000068');
    raise exception 'Event failure did not propagate';
  exception when raise_exception then
    if sqlerrm <> 'forced_r6_event_failure' then raise; end if;
  end;

  detail := public.r6_detail(a,manual_id);
  if (detail->>'starts_at')::timestamptz <> anchor + interval '10h' or detail->>'revision' <> '1'
    or not (detail->'events' @> '[{"channel":"kakao"}]') or detail::text ~ 'request_hash|confirmation_token|event_key'
    or (select count(*) from public.occupied_slots where booking_id = manual_id) <> 3
    or exists (select from public.occupied_slots where booking_id = manual_id and slot_start >= anchor + interval '10h 45min')
    or exists (select from public.occupied_slots where shop_id = a and slot_start = anchor + interval '12h')
  then raise exception 'Booking or occupied slots changed despite rollback'; end if;

  perform public.r4_save_service(a,svc,1,'Renamed', '',45,15,35000,0,'public');
  perform public.r6_change(a,manual_id,1,'move',anchor+interval '12h',null,gen_random_uuid());
  detail := public.r6_detail(a,manual_id);
  if detail->>'service_name' <> 'Fixture service' or detail->>'price_krw' <> '15000'
    or detail->>'revision' <> '2' or (detail->>'ends_at')::timestamptz <> anchor+interval '12h 30min'
    or exists (select from public.occupied_slots where booking_id = manual_id and slot_start < anchor + interval '12h')
    or (select count(*) from public.occupied_slots where booking_id = manual_id) <> 3
  then raise exception 'Reschedule changed the booking snapshot or slots'; end if;

  begin
    perform public.r6_change(a,manual_id,2,'complete',null,null,gen_random_uuid());
    raise exception 'Future booking was completed';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r6_state' then raise; end if;
  end;
  begin
    perform public.r6_change(a,manual_id,1,'cancel',null,'Wrong version',gen_random_uuid());
    raise exception 'Old version was accepted';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r6_stale' then raise; end if;
  end;

  perform public.r6_change(a,manual_id,2,'cancel',null,'Fixture cancel',cancel_key);
  replacement := public.r6_manual(a,svc,2,1,anchor+interval '12h','Fixture replacement','01000000000','phone',gen_random_uuid());
  perform public.r6_change(a,manual_id,2,'cancel',null,'Fixture cancel',cancel_key);
  if exists (select from public.occupied_slots where booking_id = manual_id)
    or (select count(*) from public.occupied_slots where booking_id = replacement) <> 4
  then raise exception 'Cancellation released the wrong slots'; end if;
  begin
    perform public.r6_change(a,manual_id,3,'move',anchor+interval '13h',null,gen_random_uuid());
    raise exception 'Cancelled booking was reopened';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r6_state' then raise; end if;
  end;

  perform public.r6_unblock(a,created_block_id);
  perform public.r6_manual(a,svc,2,1,anchor+interval '11h','After block','01000000000','phone',gen_random_uuid());
  perform public.r6_unblock(a,created_block_id);
  if exists (select from public.occupied_slots where block_id = created_block_id and shop_id = a) then
    raise exception 'Block slots remained';
  end if;

  fee_id := public.r6_manual(a,fee,1,1,anchor+interval '14h','Fee fixture','01000000000','phone',gen_random_uuid());
  if public.r6_detail(a,fee_id)->>'status' <> 'pending_deposit' then raise exception 'Manual deposit bypassed'; end if;
  perform public.r6_change(a,fee_id,1,'cancel',null,'Fee cancellation',gen_random_uuid());
  detail := public.r6_detail(a,fee_id);
  if detail->>'money_followup_status' <> 'review_needed' or detail->>'deposit_status' <> 'awaiting_transfer' then
    raise exception 'Cancellation did not preserve deposit and follow-up';
  end if;
  perform public.r6_manual(a,fee,1,1,anchor+interval '15h','Expires on read','01000000000','phone','f6000000-0000-4000-8000-000000000059');

  schedule := public.r6_schedule(a,d,d+1,'cancelled');
  if jsonb_array_length(schedule->'bookings') <> 2 or schedule::text ~ 'customer_phone|confirmation_token|Fixture block' then
    raise exception 'Schedule filter or field privacy failed';
  end if;
  begin
    perform public.r6_schedule(a,d,d+43,null);
    raise exception 'Schedule accepted an unbounded range';
  exception when invalid_parameter_value then
    if sqlerrm <> 'r6_input' then raise; end if;
  end;
  perform set_config('request.jwt.claims','{"sub":"f6000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
  if public.r6_detail(b,replacement) is not null then raise exception 'Other shop booking leaked'; end if;
  begin
    perform public.r6_change(b,replacement,1,'cancel',null,'Unauthorized',gen_random_uuid());
    raise exception 'Cross-shop booking changed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.r6_unblock(a,created_block_id);
    raise exception 'Cross-shop block was released';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- Advance the fixture deadline and put two already-created bookings in the past.
update public.bookings set deposit_due_at = now() - interval '1m', created_at = now() - interval '1h'
where idempotency_key = 'f6000000-0000-4000-8000-000000000059';
with past as (
  select b.id, case when b.customer_name = 'After block' then 1 else 2 end as days
  from public.bookings b where b.shop_id = 'f6000000-0000-4000-8000-000000000011'
    and b.customer_name in ('After block','Fixture replacement')
)
update public.occupied_slots o set slot_start = o.slot_start - make_interval(days => 3 + p.days)
from past p where o.booking_id = p.id;
update public.bookings set starts_at = starts_at - travel, ends_at = ends_at - travel, occupied_until = occupied_until - travel
from (values ('After block',interval '4 days'),('Fixture replacement',interval '5 days')) shifts(label,travel)
where shop_id = 'f6000000-0000-4000-8000-000000000011' and customer_name = label;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f6000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f6000000-0000-4000-8000-000000000011';
  d date := (now() at time zone 'Asia/Seoul')::date + 1;
  b record;
begin
  perform public.r6_schedule(a,d,d+1,null);
  if not exists (select from public.bookings where shop_id = a and customer_name = 'Expires on read' and status = 'expired')
    or exists (select from public.occupied_slots o join public.bookings v on o.booking_id=v.id where v.shop_id = a and v.customer_name = 'Expires on read')
  then raise exception 'Owner read did not expire and release'; end if;

  for b in select id,customer_name from public.bookings where shop_id = a and customer_name in ('After block','Fixture replacement') loop
    perform public.r6_change(a,b.id,2,case when b.customer_name = 'After block' then 'complete' else 'no_show' end,null,null,gen_random_uuid());
    if public.r6_detail(a,b.id)->>'status' <> (case when b.customer_name = 'After block' then 'completed' else 'no_show' end)
      or not exists (select from public.occupied_slots where booking_id = b.id) then
      raise exception 'Past outcome did not preserve slots';
    end if;
  end loop;
end;
$$;
reset role;

rollback;
select 'R6 owner schedule checks passed' as result;
