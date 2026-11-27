-- Run on a development database after R2–R7. Fixtures roll back.
begin;
set local time zone 'UTC';

insert into auth.users(id,email,email_confirmed_at) values
  ('f7000000-0000-4000-8000-000000000001','r7-a@example.invalid',now()),
  ('f7000000-0000-4000-8000-000000000002','r7-b@example.invalid',now());
insert into public.shops(id,owner_user_id,slug,name,min_notice_minutes,cancellation_policy,deposit_policy) values
  ('f7000000-0000-4000-8000-000000000011','f7000000-0000-4000-8000-000000000001','r7-test-a','Fixture A',0,'Fixture cancel','Fixture deposit'),
  ('f7000000-0000-4000-8000-000000000012','f7000000-0000-4000-8000-000000000002','r7-test-b','Fixture B',0,'','');
insert into public.services(id,shop_id,name,duration_minutes,buffer_minutes,price_krw,deposit_krw,is_public) values
  ('f7000000-0000-4000-8000-000000000021','f7000000-0000-4000-8000-000000000011','Fixture deposit service',30,15,25000,5000,true);
insert into public.shop_bank_accounts values ('f7000000-0000-4000-8000-000000000011','Fixture bank','123456','Fixture holder');
insert into public.shop_weekly_periods
select s.id, d, 'opening',540,1080 from public.shops s cross join generate_series(1,7) d where s.slug = 'r7-test-a';

do $$
declare endpoint text;
begin
  foreach endpoint in array array[
    'public.r7_record(uuid,uuid,integer,text,integer,text,boolean,uuid)',
    'public.r7_deposits(uuid,text,integer)','public.r7_deposit_detail(uuid,uuid)'
  ] loop
    if has_function_privilege('anon',endpoint,'EXECUTE') or has_function_privilege('service_role',endpoint,'EXECUTE')
      or not has_function_privilege('authenticated',endpoint,'EXECUTE')
      or not exists (select from pg_proc where oid = endpoint::regprocedure and prosecdef and 'search_path=""' = any(proconfig))
    then raise exception 'Unexpected RPC privileges'; end if;
  end loop;
  if has_function_privilege('anon','r7_private.expire_due()','EXECUTE')
    or has_function_privilege('authenticated','r7_private.expire_due()','EXECUTE')
    or has_function_privilege('service_role','r7_private.expire_due()','EXECUTE')
    or has_table_privilege('authenticated','public.bookings','UPDATE')
    or has_table_privilege('authenticated','public.occupied_slots','DELETE')
  then raise exception 'Direct or cron access granted to an application role'; end if;
end;
$$;

set local role service_role;
select public.r5_create('r7-test-a','f7000000-0000-4000-8000-000000000021',
  (((now() at time zone 'Asia/Seoul')::date + 1) + time '09:00') at time zone 'Asia/Seoul',
  1,1,'Fixture online','01000000000','r5-privacy-v1',gen_random_uuid(),'71'||repeat('a',62));
select public.r5_create('r7-test-a','f7000000-0000-4000-8000-000000000021',
  (((now() at time zone 'Asia/Seoul')::date + 1) + time '11:00') at time zone 'Asia/Seoul',
  1,1,'Fixture cancelled','01000000000','r5-privacy-v1',gen_random_uuid(),'71'||repeat('b',62));
select public.r5_create('r7-test-a','f7000000-0000-4000-8000-000000000021',
  (((now() at time zone 'Asia/Seoul')::date + 1) + time '14:00') at time zone 'Asia/Seoul',
  1,1,'Fixture reported','01000000000','r5-privacy-v1',gen_random_uuid(),'71'||repeat('c',62));
select public.r5_confirmation('71'||repeat('c',62),true)->>'depositStatus' as report_status;
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f7000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f7000000-0000-4000-8000-000000000011';
  svc constant uuid := 'f7000000-0000-4000-8000-000000000021';
  anchor timestamptz := ((now() at time zone 'Asia/Seoul')::date + 1)::timestamp at time zone 'Asia/Seoul';
  online_id uuid;
  manual_id uuid;
  cancelled_id uuid;
  mismatch_id uuid;
  request_id uuid := gen_random_uuid();
  refund_key uuid := gen_random_uuid();
  detail jsonb;
begin
  select id into online_id from public.bookings where shop_id = a and customer_name = 'Fixture online';
  select id into cancelled_id from public.bookings where shop_id = a and customer_name = 'Fixture cancelled';
  manual_id := public.r6_manual(a,svc,1,1,anchor+interval '10h','Fixture manual','01000000000','phone',gen_random_uuid());
  if public.r7_record(a,online_id,1,'confirm',5000,null,false,gen_random_uuid()) <> 'r7_input'
    or public.r7_record(a,online_id,1,'confirm',5000,null,true,request_id) <> 'deposit_verified'
    or public.r7_record(a,online_id,1,'confirm',5000,null,true,request_id) <> 'deposit_verified'
    or public.r7_record(a,online_id,1,'confirm',5000,'changed',true,request_id) <> 'r7_key'
    or public.r7_record(a,online_id,2,'confirm',5000,null,true,gen_random_uuid()) <> 'r7_state'
  then raise exception 'Online approval or idempotency failed'; end if;
  detail := public.r7_deposit_detail(a,online_id);
  if detail->>'status' <> 'confirmed' or detail->>'deposit_status' <> 'verified'
    or jsonb_array_length(detail->'events') <> 1 or detail::text ~ 'confirmation_token|customer_phone|123456'
    or (select count(*) from public.occupied_slots where booking_id = online_id) <> 3
    or not exists (select from public.bookings where id = online_id and deposit_verified_by =
      'f7000000-0000-4000-8000-000000000001' and deposit_verified_at is not null)
  then raise exception 'Approval changed schedule, leaked fields, or lost audit'; end if;

  if public.r7_record(a,manual_id,1,'confirm',5000,null,true,gen_random_uuid()) <> 'deposit_verified' then
    raise exception 'Manual booking was not confirmed';
  end if;
  perform public.r6_change(a,manual_id,2,'cancel',null,'Fixture cancellation',gen_random_uuid());
  if public.r7_record(a,manual_id,3,'refund',5001,'Over cap',true,gen_random_uuid()) <> 'r7_amount'
    or public.r7_record(a,manual_id,3,'refund',3000,'Manual refund fixture',true,refund_key) <> 'manual_refund_recorded'
    or public.r7_record(a,manual_id,3,'refund',3000,'Manual refund fixture',true,refund_key) <> 'manual_refund_recorded'
    or public.r7_record(a,manual_id,4,'refund',1000,'Already closed',true,gen_random_uuid()) <> 'r7_state'
  then raise exception 'Manual refund, cap, or replay failed'; end if;
  detail := public.r7_deposit_detail(a,manual_id);
  if detail->>'status' <> 'cancelled' or detail->>'money_followup_status' <> 'resolved_recorded'
    or detail->>'refundable_krw' <> '2000' or exists (select from public.occupied_slots where booking_id = manual_id)
  then raise exception 'Refund record altered the reservation'; end if;

  perform public.r6_change(a,cancelled_id,1,'cancel',null,'Fixture cancellation',gen_random_uuid());
  if public.r7_record(a,cancelled_id,2,'no_refund',0,'No transfer at review',true,gen_random_uuid()) <> 'no_refund_recorded'
  then raise exception 'Initial no-refund review did not close'; end if;

  mismatch_id := public.r6_manual(a,svc,1,1,anchor+interval '16h','Fixture mismatch','01000000000','phone',gen_random_uuid());
  if public.r7_record(a,mismatch_id,1,'confirm',3000,null,true,gen_random_uuid()) <> 'r7_reason'
    or public.r7_record(a,mismatch_id,1,'confirm',3000,'Partial transfer',true,gen_random_uuid()) <> 'deposit_discrepancy'
    or public.r7_record(a,mismatch_id,2,'confirm',3000,'Partial transfer',true,gen_random_uuid()) <> 'r7_duplicate'
    or public.r7_deposit_detail(a,mismatch_id)->>'status' <> 'pending_deposit'
    or public.r7_deposits(a,'review',1)#>>'{counts,review}' <> '1'
  then raise exception 'Mismatched transfer was approved, duplicated, or omitted from review'; end if;

  perform public.r6_manual(a,svc,1,1,anchor+interval '15h','Fixture cron','01000000000','phone',gen_random_uuid());
  perform public.r6_manual(a,svc,1,1,anchor+interval '17h','Fixture overdue','01000000000','phone',gen_random_uuid());

  perform set_config('request.jwt.claims','{"sub":"f7000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
  if public.r7_deposit_detail('f7000000-0000-4000-8000-000000000012',online_id) is not null
    or public.r7_record('f7000000-0000-4000-8000-000000000012',online_id,2,'confirm',5000,null,true,gen_random_uuid()) <> 'r7_missing'
  then raise exception 'Other shop booking exposed'; end if;
end;
$$;
reset role;

set local role service_role;
do $$
declare first_report jsonb;
begin
  first_report := public.r5_confirmation('71'||repeat('b',62),true);
  if first_report->>'status' <> 'cancelled' or first_report->>'followup' <> 'review_needed'
    or (public.r5_confirmation('71'||repeat('b',62),true)->>'canReport')::boolean
  then raise exception 'Customer late report did not reopen or was repeated'; end if;
end;
$$;
reset role;

-- Advance only the fixture deadlines.
update public.bookings set deposit_due_at = now() - interval '1 minute', created_at = now() - interval '1 hour'
where shop_id = 'f7000000-0000-4000-8000-000000000011' and customer_name in
  ('Fixture reported','Fixture cron','Fixture mismatch','Fixture overdue');

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f7000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f7000000-0000-4000-8000-000000000011';
  overdue uuid;
  late uuid;
  reported uuid;
  detail jsonb;
begin
  select id into overdue from public.bookings where shop_id = a and customer_name = 'Fixture overdue';
  select id into late from public.bookings where shop_id = a and customer_name = 'Fixture cancelled';
  select id into reported from public.bookings where shop_id = a and customer_name = 'Fixture reported';
  if public.r7_record(a,overdue,2,'confirm',5000,null,true,gen_random_uuid()) <> 'r7_stale' then
    raise exception 'Overdue unreported booking did not expire before approval';
  end if;
  if exists (select from public.occupied_slots where booking_id = overdue) then raise exception 'Expiry did not release slots'; end if;
  if public.r7_record(a,reported,3,'confirm',5000,null,true,gen_random_uuid()) <> 'deposit_verified' then
    raise exception 'Reported booking lost its approval eligibility';
  end if;
  if public.r7_record(a,late,3,'receipt',6500,'Old revision',true,gen_random_uuid()) <> 'r7_stale'
    or public.r7_record(a,late,4,'receipt',6500,'Late transfer',true,gen_random_uuid()) <> 'deposit_verified_after_close'
  then raise exception 'Late receipt or revision validation failed'; end if;
  detail := public.r7_deposit_detail(a,late);
  if detail->>'status' <> 'cancelled' or detail->>'deposit_status' <> 'verified'
    or detail->>'refundable_krw' <> '6500' or exists (select from public.occupied_slots where booking_id = late)
  then raise exception 'Late receipt reopened a cancelled booking or lost actual amount'; end if;
end;
$$;
reset role;

-- The owner approval call committed reactive expiry even though it denied approval.
do $$
begin
  if not exists (select from public.bookings where shop_id = 'f7000000-0000-4000-8000-000000000011'
      and customer_name = 'Fixture mismatch' and status = 'expired' and money_followup_status = 'review_needed')
  then raise exception 'Partial deposit evidence was lost on expiry'; end if;
end;
$$;

rollback;
select 'R7 deposit checks passed' as result;
