-- Run as the local database administrator after applying the migration.
-- Use psql with ON_ERROR_STOP=1. The fixtures and role changes are rolled back.
begin;
set local time zone 'UTC';

insert into auth.users (id, email) values
  ('f2000000-0000-4000-8000-000000000001', 'r2-owner-a@example.invalid'),
  ('f2000000-0000-4000-8000-000000000002', 'r2-owner-b@example.invalid');

insert into public.shops (id, owner_user_id, slug, name) values
  ('f2000000-0000-4000-8000-000000000011', 'f2000000-0000-4000-8000-000000000001', 'r2-test-a', 'Test shop A'),
  ('f2000000-0000-4000-8000-000000000012', 'f2000000-0000-4000-8000-000000000002', 'r2-test-b', 'Test shop B');

insert into public.shop_weekly_periods (shop_id, iso_weekday, period_kind, start_minute, end_minute)
select id, 1, 'opening', 540, 1080 from public.shops where slug in ('r2-test-a', 'r2-test-b');

insert into public.services (id, shop_id, name, duration_minutes, buffer_minutes, price_krw, is_public) values
  ('f2000000-0000-4000-8000-000000000021', 'f2000000-0000-4000-8000-000000000011', 'Test service A', 30, 15, 10000, true),
  ('f2000000-0000-4000-8000-000000000022', 'f2000000-0000-4000-8000-000000000012', 'Test service B', 30, 15, 10000, false);

insert into public.shop_bank_accounts (shop_id, bank_name, account_number, account_holder)
select id, 'Test bank', 'fixture-only', name from public.shops where slug in ('r2-test-a', 'r2-test-b');

insert into public.bookings (
  id, shop_id, service_id, source, customer_name, customer_phone, starts_at, ends_at, occupied_until,
  status, deposit_status, service_revision, shop_policy_revision, service_name, duration_minutes,
  buffer_minutes, price_krw, deposit_krw, cancellation_notice_minutes, cancellation_policy, deposit_policy,
  confirmation_token_hash, idempotency_key, request_hash
)
select
  fixture.booking_id, service.shop_id, service.id, fixture.source, 'Test customer', 'fixture-only',
  timestamptz '2030-01-07 00:00:00+09', timestamptz '2030-01-07 00:30:00+09', timestamptz '2030-01-07 00:45:00+09',
  'confirmed', 'not_required', service.revision, 1, service.name, service.duration_minutes,
  service.buffer_minutes, service.price_krw, 0, 0, '', '',
  fixture.token_hash, 'f2000000-0000-4000-8000-000000000090'::uuid, decode(repeat('02', 32), 'hex')
from (
  values
    ('f2000000-0000-4000-8000-000000000031'::uuid, 'f2000000-0000-4000-8000-000000000021'::uuid,
      'online', decode(repeat('01', 32), 'hex')),
    ('f2000000-0000-4000-8000-000000000032'::uuid, 'f2000000-0000-4000-8000-000000000022'::uuid,
      'manual', null)
) as fixture(booking_id, service_id, source, token_hash)
join public.services as service on service.id = fixture.service_id;

insert into public.occupied_slots (shop_id, slot_start, booking_id)
select booking.shop_id, slot.start_at, booking.id
from public.bookings as booking
cross join lateral generate_series(
  booking.starts_at, booking.occupied_until - interval '15 minutes', interval '15 minutes'
) as slot(start_at)
where booking.id in ('f2000000-0000-4000-8000-000000000031', 'f2000000-0000-4000-8000-000000000032');

insert into public.blocks (id, shop_id, starts_at, ends_at) values
  ('f2000000-0000-4000-8000-000000000041', 'f2000000-0000-4000-8000-000000000011',
    '2030-01-07 00:45:00+09', '2030-01-07 01:00:00+09'),
  ('f2000000-0000-4000-8000-000000000042', 'f2000000-0000-4000-8000-000000000012',
    '2030-01-07 00:45:00+09', '2030-01-07 01:00:00+09');

insert into public.occupied_slots (shop_id, slot_start, block_id)
select shop_id, starts_at, id
from public.blocks where id in ('f2000000-0000-4000-8000-000000000041', 'f2000000-0000-4000-8000-000000000042');

insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind)
select shop_id, id, 'created', 'f2000000-0000-4000-8000-000000000091', 'system'
from public.bookings where id in ('f2000000-0000-4000-8000-000000000031', 'f2000000-0000-4000-8000-000000000032');

do $$
declare
  a_shop constant uuid := 'f2000000-0000-4000-8000-000000000011';
  a_service constant uuid := 'f2000000-0000-4000-8000-000000000021';
  a_booking constant uuid := 'f2000000-0000-4000-8000-000000000031';
  b_booking constant uuid := 'f2000000-0000-4000-8000-000000000032';
  a_block constant uuid := 'f2000000-0000-4000-8000-000000000041';
  candidate uuid;
begin
  if not exists (
    select from public.bookings
    where id = a_booking
      and starts_at = timestamptz '2030-01-06 15:00:00+00'
      and (starts_at at time zone 'Asia/Seoul')::date = date '2030-01-07'
  ) then
    raise exception 'Seoul midnight must be the same instant as the prior UTC day at 15:00';
  end if;

  if (select count(*) from public.occupied_slots
      where shop_id = a_shop and (booking_id = a_booking or block_id = a_block)) <> 4 then
    raise exception 'Expected three booking slots and the adjacent block';
  end if;

  begin
    insert into public.shops (owner_user_id, slug, name)
    values ('f2000000-0000-4000-8000-000000000001', 'r2-duplicate-owner', 'Duplicate');
    raise exception 'A second shop for the same owner was accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into public.occupied_slots (shop_id, slot_start, booking_id)
    values (a_shop, '2030-01-07 01:00:00+09', b_booking);
    raise exception 'A slot linked to a booking in another shop';
  exception when foreign_key_violation then null;
  end;

  begin
    insert into public.occupied_slots (shop_id, slot_start, booking_id, block_id)
    values (a_shop, '2030-01-07 01:00:00+09', a_booking, a_block);
    raise exception 'A slot linked to both a booking and a block';
  exception when check_violation then null;
  end;

  begin
    insert into public.occupied_slots (shop_id, slot_start, booking_id)
    values (a_shop, '2030-01-07 00:07:00+09', a_booking);
    raise exception 'An off-grid slot was accepted';
  exception when check_violation then null;
  end;

  begin
    update public.bookings set service_id = 'f2000000-0000-4000-8000-000000000022' where id = a_booking;
    raise exception 'A booking linked to a service in another shop';
  exception when foreign_key_violation then null;
  end;

  begin
    update public.services set deposit_krw = price_krw + 1 where id = a_service;
    raise exception 'A deposit greater than the service price was accepted';
  exception when check_violation then null;
  end;

  begin
    update public.bookings set status = 'pending_deposit' where id = a_booking;
    raise exception 'A no-deposit booking was accepted in a deposit-pending state';
  exception when check_violation then null;
  end;

  update public.bookings
  set deposit_krw = 5000, status = 'pending_deposit', deposit_status = 'reported',
      created_at = starts_at - interval '60 minutes', deposit_due_at = starts_at,
      deposit_bank_name = 'Test bank', deposit_account_number = 'fixture-only',
      deposit_account_holder = 'Test shop A'
  where id = a_booking;

  begin
    update public.bookings set status = 'confirmed' where id = a_booking;
    raise exception 'A deposit report was accepted as confirmation';
  exception when check_violation then null;
  end;

  begin
    update public.bookings set status = 'expired' where id = a_booking;
    raise exception 'A reported deposit was accepted in an expired booking';
  exception when check_violation then null;
  end;

  begin
    insert into public.blocks (shop_id, starts_at, ends_at)
    values (a_shop, '2030-01-07 00:30:00+09', '2030-01-07 00:45:00+09')
    returning id into candidate;
    insert into public.occupied_slots (shop_id, slot_start, block_id)
    values (a_shop, '2030-01-07 00:30:00+09', candidate);
    raise exception 'A block overlapped the online booking buffer';
  exception when unique_violation then null;
  end;

  begin
    insert into public.bookings (
      shop_id, service_id, source, customer_name, customer_phone, starts_at, ends_at, occupied_until,
      status, deposit_status, service_revision, shop_policy_revision, service_name, duration_minutes,
      buffer_minutes, price_krw, deposit_krw, cancellation_notice_minutes, cancellation_policy, deposit_policy,
      idempotency_key, request_hash
    )
    values (
      a_shop, a_service, 'manual', 'Test customer', 'fixture-only',
      '2030-01-07 00:30:00+09', '2030-01-07 01:00:00+09', '2030-01-07 01:15:00+09',
      'confirmed', 'not_required', 1, 1, 'Test service A', 30, 15, 10000, 0, 0, '', '',
      'f2000000-0000-4000-8000-000000000092', decode(repeat('03', 32), 'hex')
    ) returning id into candidate;
    insert into public.occupied_slots (shop_id, slot_start, booking_id)
    values (a_shop, '2030-01-07 00:30:00+09', candidate);
    raise exception 'A manual booking overlapped the online booking buffer';
  exception when unique_violation then null;
  end;
end
$$;

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

do $$
declare
  relation text;
begin
  foreach relation in array array[
    'shops', 'shop_weekly_periods', 'services', 'shop_bank_accounts',
    'bookings', 'blocks', 'occupied_slots', 'booking_events'
  ] loop
    begin
      execute format('select 1 from public.%I limit 1', relation);
      raise exception 'anon can read %', relation;
    exception when insufficient_privilege then null;
    end;
    if has_table_privilege('public.' || relation, 'INSERT, UPDATE, DELETE, TRUNCATE')
      or has_any_column_privilege('public.' || relation, 'INSERT, UPDATE') then
      raise exception 'anon can write %', relation;
    end if;
  end loop;
end
$$;

reset role;
set local role authenticated;

do $$
declare
  owners constant uuid[] := array[
    'f2000000-0000-4000-8000-000000000001'::uuid, 'f2000000-0000-4000-8000-000000000002'::uuid
  ];
  shops constant uuid[] := array[
    'f2000000-0000-4000-8000-000000000011'::uuid, 'f2000000-0000-4000-8000-000000000012'::uuid
  ];
  relation text;
  shop_column text;
  expected_count integer;
  own_count bigint;
  other_count bigint;
  hidden_column text;
begin
  for owner_index in 1..2 loop
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', owners[owner_index], 'role', 'authenticated', 'is_anonymous', false
    )::text, true);
    foreach relation in array array[
      'shops', 'shop_weekly_periods', 'services', 'shop_bank_accounts',
      'bookings', 'blocks', 'occupied_slots', 'booking_events'
    ] loop
      shop_column := case when relation = 'shops' then 'id' else 'shop_id' end;
      expected_count := case when relation = 'occupied_slots' then 4 else 1 end;
      execute format('select count(*) filter (where %I = $1), count(*) filter (where %I <> $1) from public.%I',
        shop_column, shop_column, relation)
      into own_count, other_count using shops[owner_index];
      if own_count <> expected_count or other_count <> 0 then
        raise exception 'Owner % has unexpected visibility on %: own %, other %',
          owner_index, relation, own_count, other_count;
      end if;
      if has_table_privilege('public.' || relation, 'INSERT, UPDATE, DELETE, TRUNCATE')
        or has_any_column_privilege('public.' || relation, 'INSERT, UPDATE') then
        raise exception 'authenticated can directly write %', relation;
      end if;
    end loop;

    if not exists (select from public.bookings where shop_id = shops[owner_index] and customer_phone = 'fixture-only') then
      raise exception 'Owner % cannot read their booking contact column', owner_index;
    end if;

    foreach hidden_column in array array['confirmation_token_hash', 'idempotency_key', 'request_hash', 'deposit_account_number']
    loop
      begin
        execute format('select %I from public.bookings', hidden_column);
        raise exception 'authenticated can read private booking column %', hidden_column;
      exception when insufficient_privilege then null;
      end;
    end loop;

    begin
      update public.services set name = 'Forbidden' where shop_id = shops[3 - owner_index];
      raise exception 'Owner % can update another shop service', owner_index;
    exception when insufficient_privilege then null;
    end;
  end loop;

  begin
    perform details from public.booking_events;
    raise exception 'authenticated can read private event details';
  exception when insufficient_privilege then null;
  end;

  -- Use the same subject as A to prove the anonymous JWT claim itself blocks access.
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', owners[1], 'role', 'authenticated', 'is_anonymous', true
  )::text, true);
  if exists (select id from public.shops) or exists (select id from public.bookings) then
    raise exception 'Anonymous sign-in sees business rows';
  end if;
end
$$;

reset role;
set local role service_role;

do $$
begin
  if (select count(*) from public.bookings
      where id in ('f2000000-0000-4000-8000-000000000031', 'f2000000-0000-4000-8000-000000000032')) <> 2 then
    raise exception 'Expected service_role to bypass RLS';
  end if;

  begin
    delete from public.occupied_slots where false;
    raise exception 'service_role can directly delete slots';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;
rollback;
select 'R2 foundation checks passed' as result;
