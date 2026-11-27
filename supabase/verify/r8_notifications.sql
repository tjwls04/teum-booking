-- Run on a development database after R2–R8. Fixtures roll back. No HTTP calls.
begin;
set local time zone 'UTC';

insert into auth.users (id,email,email_confirmed_at) values
  ('f8000000-0000-4000-8000-000000000001','r8-a@example.invalid',now()),
  ('f8000000-0000-4000-8000-000000000002','r8-b@example.invalid',now());
insert into public.shops (id,owner_user_id,slug,name,min_notice_minutes,cancellation_policy,deposit_policy) values
  ('f8000000-0000-4000-8000-000000000011','f8000000-0000-4000-8000-000000000001','r8-test-a','Fixture A',0,'Cancellation policy','Deposit policy'),
  ('f8000000-0000-4000-8000-000000000012','f8000000-0000-4000-8000-000000000002','r8-test-b','Fixture B',0,'','');
insert into public.services (id,shop_id,name,duration_minutes,price_krw,deposit_krw,is_public) values
  ('f8000000-0000-4000-8000-000000000021','f8000000-0000-4000-8000-000000000011','Service A',30,20000,5000,true),
  ('f8000000-0000-4000-8000-000000000022','f8000000-0000-4000-8000-000000000012','Service B',30,20000,0,true);
insert into public.shop_bank_accounts values
  ('f8000000-0000-4000-8000-000000000011','Fixture bank','123456','Fixture holder');
insert into public.shop_weekly_periods
select s.id,d,'opening',540,1080 from public.shops s cross join generate_series(1,7) d where s.slug in ('r8-test-a','r8-test-b');

do $$
declare f record;
begin
  for f in select oid,proname,prosecdef,proconfig from pg_proc
    where pronamespace = 'public'::regnamespace and proname like 'r8\_%'
  loop
    if not f.prosecdef or ('search_path=""' = any(f.proconfig)) is distinct from true
      or has_function_privilege('anon',f.oid,'EXECUTE')
      or has_function_privilege('service_role',f.oid,'EXECUTE') <> (f.proname in ('r8_scan','r8_claim','r8_finish'))
      or has_function_privilege('authenticated',f.oid,'EXECUTE') = (f.proname in ('r8_scan','r8_claim','r8_finish'))
    then raise exception 'R8 RPC permissions differ from declared access'; end if;
  end loop;
  if has_schema_privilege('authenticated','r8_private','USAGE') or has_schema_privilege('anon','r8_private','USAGE')
    or has_schema_privilege('service_role','r8_private','USAGE')
    or exists (select from pg_class where relnamespace = 'r8_private'::regnamespace and relkind = 'r' and not relrowsecurity)
  then raise exception 'R8 data is directly accessible'; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f8000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f8000000-0000-4000-8000-000000000011';
  endpoint constant text := 'https://fcm.googleapis.com/fcm/send/r8-device-a';
  bad text;
begin
  foreach bad in array array[
    'http://fcm.googleapis.com/fcm/send/r8-device-a','https://127.0.0.1/fcm/send/r8-device-a',
    'https://fcm.googleapis.com.example.invalid/fcm/send/r8-device-a',
    'https://fcm.googleapis.com@127.0.0.1/fcm/send/r8-device-a',
    'https://fcm.googleapis.com:443/fcm/send/r8-device-a','https://web.push.apple.com/r8-device-a?next=bad',
    'https://fcm.googleapis.com/fcm/send/%2e%2e/r8-device-a'
  ] loop
    begin
      perform public.r8_register(a,bad,'B'||repeat('A',86),repeat('A',22));
      raise exception 'Invalid endpoint accepted';
    exception when invalid_parameter_value then null;
    end;
  end loop;
  perform public.r8_register(a,endpoint,'B'||repeat('A',86),repeat('A',22));
  perform public.r8_register(a,endpoint,'B'||repeat('A',86),repeat('A',22));
  if jsonb_array_length(public.r8_preferences(a)->'devices') <> 1
    or public.r8_preferences(a)::text ~ 'endpoint|p256dh|auth_secret' then raise exception 'Device duplicated or leaked'; end if;
end;
$$;
select set_config('request.jwt.claims','{"sub":"f8000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
select public.r8_register('f8000000-0000-4000-8000-000000000012',
  'https://updates.push.services.mozilla.com/wpush/v2/r8-device-b','B'||repeat('A',86),repeat('A',22));
select public.r8_set_enabled('f8000000-0000-4000-8000-000000000012',false);
reset role;

set local role service_role;
do $$
declare
  a_svc constant uuid := 'f8000000-0000-4000-8000-000000000021';
  b_svc constant uuid := 'f8000000-0000-4000-8000-000000000022';
  day_start timestamptz := ((now() at time zone 'Asia/Seoul')::date + 1)::timestamp at time zone 'Asia/Seoul';
  key uuid := gen_random_uuid();
begin
  perform public.r5_create('r8-test-a',a_svc,day_start+interval '10 hours',1,1,
    'Sensitive fixture A','01000000000','r5-privacy-v1',key,'81'||repeat('a',62));
  if public.r5_create('r8-test-a',a_svc,day_start+interval '10 hours',1,1,
    'Sensitive fixture A','01000000000','r5-privacy-v1',key,'81'||repeat('a',62)) <> '{"created":false}' then
    raise exception 'Reservation replay failed';
  end if;
  perform public.r5_confirmation('81'||repeat('a',62),true);
  perform public.r5_confirmation('81'||repeat('a',62),true);
  perform public.r5_create('r8-test-a',a_svc,day_start+interval '12 hours',1,1,
    'Sensitive fixture expiry','01000000000','r5-privacy-v1',gen_random_uuid(),'81'||repeat('b',62));
  perform public.r5_create('r8-test-b',b_svc,day_start+interval '10 hours',1,1,
    'Sensitive fixture B','01000000000','r5-privacy-v1',gen_random_uuid(),'81'||repeat('c',62));
  begin
    perform public.r5_create('r8-test-a',a_svc,day_start+interval '14 hours',1,1,
      'Sensitive fixture rollback','01000000000','r5-privacy-v1',gen_random_uuid(),'81'||repeat('d',62));
    raise exception using message = 'fixture rollback',errcode = 'PT409';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'fixture rollback' then raise; end if;
  end;
end;
$$;
reset role;

update public.bookings set created_at = now() - interval '2 hours',deposit_due_at = now() - interval '1 hour'
where shop_id = 'f8000000-0000-4000-8000-000000000011';
select r7_private.expire_shop('f8000000-0000-4000-8000-000000000011',now(),100);

set local role service_role;
select public.r5_confirmation('81'||repeat('b',62),true)->>'status' as late_report_status;
select public.r5_confirmation('81'||repeat('b',62),true)->>'status' as late_report_replay;
reset role;

do $$
declare
  a constant uuid := 'f8000000-0000-4000-8000-000000000011';
  b constant uuid := 'f8000000-0000-4000-8000-000000000012';
  simulated timestamptz := (((now() at time zone 'Asia/Seoul')::date + 1) + time '08:00') at time zone 'Asia/Seoul';
begin
  perform r8_private.scan(clock_timestamp(),a);
  perform r8_private.scan(clock_timestamp(),a);
  perform r8_private.scan(simulated,a);
  perform r8_private.scan(simulated,a);
  perform r8_private.scan(simulated,b);
  if (select count(*) from r8_private.inbox where shop_id = 'f8000000-0000-4000-8000-000000000011') <> 7
    or (select count(distinct kind) from r8_private.inbox where shop_id = 'f8000000-0000-4000-8000-000000000011') <> 6
    or (select count(*) from r8_private.jobs where shop_id = 'f8000000-0000-4000-8000-000000000011') <> 7
    or (select count(*) from r8_private.inbox where shop_id = 'f8000000-0000-4000-8000-000000000012') <> 2
  then raise exception 'Missing or duplicate event / scheduled inbox jobs, or rollback failed'; end if;
  if exists (select from public.bookings where customer_name = 'Sensitive fixture rollback')
    or not exists (select from public.bookings b join public.occupied_slots o on o.booking_id = b.id
        where b.customer_name = 'Sensitive fixture A' and b.status = 'pending_deposit' and b.deposit_status = 'reported')
    or exists (select from public.bookings b join public.occupied_slots o on o.booking_id = b.id
        where b.customer_name = 'Sensitive fixture expiry')
  then raise exception 'Notification changed booking or slot state'; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f8000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$
declare
  a constant uuid := 'f8000000-0000-4000-8000-000000000011';
  b constant uuid := 'f8000000-0000-4000-8000-000000000012';
  row_data jsonb := public.r8_inbox(a,true,null,null)->0;
  id uuid := (row_data->>'id')::uuid;
  device_id uuid := (public.r8_preferences(a)#>>'{devices,0,id}')::uuid;
begin
  if public.r8_unread(a) <> 7 or row_data::text ~ 'Sensitive|customer|phone|123456'
    or public.r8_target(a,id)->>'kind' is distinct from row_data->>'kind'
    or jsonb_array_length(public.r8_inbox(a,false,(row_data->>'created_at')::timestamptz,id)) <> 6 then
    raise exception 'Inbox unread, cursor or target not correctly scoped';
  end if;
  perform public.r8_read(a,id,true);
  if public.r8_unread(a) <> 6 then raise exception 'Mark reading failed'; end if;
  perform public.r8_read(a,id,false);
  if public.r8_unread(a) <> 7 then raise exception 'Mark unread failed'; end if;
  perform public.r8_read(a,null,true);
  if public.r8_unread(a) <> 0 then raise exception 'Mark all reading failed'; end if;

  perform set_config('request.jwt.claims','{"sub":"f8000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
  begin
    perform public.r8_inbox(a,false,null,null);
    raise exception 'Another shop inbox exposed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.r8_set_enabled(a,false);
    raise exception 'Another shop setting changed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.r8_register(b,'https://fcm.googleapis.com/fcm/send/r8-device-a','B'||repeat('A',86),repeat('A',22));
    raise exception 'Another shop endpoint was taken';
  exception when sqlstate 'PT409' then null;
  end;
  perform public.r8_remove(b,device_id,null);
  perform public.r8_read(b,id,false);
  if public.r8_unread(b) <> 2 or public.r8_target(b,id) is not null then raise exception 'Cross-shop notification exposed'; end if;
  perform public.r8_set_enabled(b,true);

  perform set_config('request.jwt.claims','{"sub":"f8000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}',true);
  begin
    perform public.r8_unread(a);
    raise exception 'Anonymous authenticated account saw an inbox';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

do $$
declare
  leased jsonb := r8_private.claim('f8000000-0000-4000-8000-000000000011');
  item jsonb;
begin
  if r8_private.claim('f8000000-0000-4000-8000-000000000012') <> '[]' then
    raise exception 'Notifications created when push was off were dispatched after opt-in';
  end if;
  if jsonb_array_length(leased) <> 7 or r8_private.claim('f8000000-0000-4000-8000-000000000011') <> '[]'
    or leased::text ~ 'Sensitive|customer|phone|123456|booking_id'
  then raise exception 'Delivery lease, scope, fanout or projection failed'; end if;
  for item in select value from jsonb_array_elements(leased)
  loop
    if not public.r8_finish((item->>'id')::uuid,(item->>'lease_token')::uuid,'retry','http_429',120) then
      raise exception 'Retry result was not saved';
    end if;
  end loop;
  if r8_private.claim('f8000000-0000-4000-8000-000000000011') <> '[]' then raise exception 'Backoff ignored'; end if;
end;
$$;

do $$
begin
  if (select count(*) from r8_private.deliveries where shop_id = 'f8000000-0000-4000-8000-000000000011'
      and attempts = 1 and last_error = 'http_429' and next_at >= clock_timestamp() + interval '110 seconds') <> 7
  then raise exception 'Retry metadata not saved'; end if;
end;
$$;
update r8_private.deliveries set next_at = now() - interval '1 second',lease_token = gen_random_uuid(),
  lease_until = now() - interval '1 second',attempts = 4
where shop_id = 'f8000000-0000-4000-8000-000000000011';
select set_config('r8.fixture.old_lease',(select lease_token::text from r8_private.deliveries
  where shop_id = 'f8000000-0000-4000-8000-000000000011' order by id limit 1),true);

do $$
declare
  leased jsonb := r8_private.claim('f8000000-0000-4000-8000-000000000011');
  item jsonb := (select value from jsonb_array_elements(leased) order by value->>'id' limit 1);
  target uuid := (item->>'id')::uuid;
  lease uuid := (item->>'lease_token')::uuid;
begin
  if jsonb_array_length(leased) <> 7 or lease = current_setting('r8.fixture.old_lease')::uuid
    or public.r8_finish(target,current_setting('r8.fixture.old_lease')::uuid,'sent',null,null)
  then raise exception 'Expired lease was not safely reclaimed'; end if;
  if not public.r8_finish(target,lease,'retry','network',null)
    or public.r8_finish(target,lease,'sent',null,null) then raise exception 'Fifth attempt or stale finish failed'; end if;
  item := (select value from jsonb_array_elements(leased) where value->>'id' <> target::text limit 1);
  if not public.r8_finish((item->>'id')::uuid,(item->>'lease_token')::uuid,'gone','http_410',null)
  then raise exception 'Gone subscription was not handled'; end if;
end;
$$;

update r8_private.deliveries set lease_until = now() - interval '1 second'
where shop_id = 'f8000000-0000-4000-8000-000000000011' and status = 'pending';
select jsonb_array_length(r8_private.claim('f8000000-0000-4000-8000-000000000011')) as remaining;

do $$
begin
  if exists (select from r8_private.devices where shop_id = 'f8000000-0000-4000-8000-000000000011'
      and num_nonnulls(endpoint,p256dh,auth_secret) > 0)
    or (select count(*) from r8_private.deliveries where shop_id = 'f8000000-0000-4000-8000-000000000011' and status = 'failed' and attempts = 5) <> 7
    or (select count(*) from r8_private.deliveries where shop_id = 'f8000000-0000-4000-8000-000000000011' and last_error = 'lease_exhausted') <> 5
  then raise exception 'Subscription cleanup or final failure tracking failed'; end if;
end;
$$;

rollback;
select 'R8 notification checks passed' as result;
