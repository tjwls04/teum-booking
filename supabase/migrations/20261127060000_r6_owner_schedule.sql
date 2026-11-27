-- Apply the whole file in a single transaction.
create schema r6_private;
revoke all on schema r6_private from public, anon, authenticated, service_role;

alter table public.bookings add column revision integer not null default 1 check (revision > 0);
alter table public.blocks add column released_at timestamptz;
create index r6_booking_range_idx on public.bookings (shop_id, occupied_until, starts_at);
create index r6_active_blocks_range_idx on public.blocks (shop_id, ends_at, starts_at) where released_at is null;

create function r6_private.bump_revision() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.revision := old.revision + 1;
  return new;
end;
$$;
create trigger r6_booking_revision before update on public.bookings
for each row execute function r6_private.bump_revision();

create function r6_private.on_grid(p_start timestamptz)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_start >= timestamptz '2000-01-01 00:00+00'
    and p_start < timestamptz '2100-01-01 00:00+00'
    and p_start = date_bin(interval '15 min', p_start, timestamptz '2000-01-01 00:00+09'), false)
$$;

create function public.r6_manual(
  p_shop uuid, p_service uuid, p_service_revision integer, p_policy integer,
  p_start timestamptz, p_name text, p_phone text, p_channel text, p_key uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
  svc public.services;
  booking public.bookings;
  account public.shop_bank_accounts;
  baseline timestamptz := clock_timestamp();
  fingerprint bytea;
  finish timestamptz;
  occupied_end timestamptz;
begin
  p_name := r4_private.clean_text(p_name);
  p_phone := regexp_replace(coalesce(p_phone, ''), '[ -]', '', 'g');
  if p_key is null or p_service is null or p_service_revision is null or p_policy is null
    or not r6_private.on_grid(p_start) or p_name is null or char_length(p_name) not between 1 and 60
    or p_name ~ '[[:cntrl:]]' or p_phone !~ '^01[016789][0-9]{7,8}$'
    or p_channel is null or p_channel not in ('kakao', 'phone') then
    raise exception using errcode = '22023', message = 'r6_input';
  end if;
  fingerprint := sha256(convert_to(jsonb_build_array(
    'manual', p_service, extract(epoch from p_start), p_service_revision, p_policy, p_name, p_phone, p_channel
  )::text, 'UTF8'));
  perform r5_private.expire(shop.id, baseline);
  select * into booking from public.bookings b where b.shop_id = shop.id and b.idempotency_key = p_key;
  if found then
    if booking.source <> 'manual' or booking.request_hash <> fingerprint then
      raise exception using errcode = 'PT409', message = 'r6_key';
    end if;
    return booking.id;
  end if;
  select * into svc from public.services s where s.shop_id = shop.id and s.id = p_service and s.is_active;
  if not found or svc.revision <> p_service_revision or shop.policy_revision <> p_policy then
    raise exception using errcode = 'PT409', message = 'r6_stale';
  end if;
  -- The owner can take a near-term booking, with the same hours and occupied slots as online.
  shop.min_notice_minutes := 0;
  if svc.duration_minutes::bigint + svc.buffer_minutes > 1440 or not r5_private.can_book(shop, svc, p_start, baseline) then
    raise exception using errcode = 'PT409', message = 'r6_time';
  end if;
  if svc.deposit_krw > 0 then
    select * into account from public.shop_bank_accounts a where a.shop_id = shop.id;
    if not found or not r4_private.valid_bank(account.bank_name, account.account_number, account.account_holder)
      or r4_private.clean_text(shop.deposit_policy) = '' or r4_private.clean_text(shop.cancellation_policy) = '' then
      raise exception using errcode = 'PT409', message = 'r6_deposit';
    end if;
  end if;
  finish := p_start + make_interval(mins => svc.duration_minutes);
  occupied_end := finish + make_interval(mins => svc.buffer_minutes);
  insert into public.bookings (
    shop_id, service_id, source, customer_name, customer_phone, starts_at, ends_at, occupied_until,
    status, deposit_status, service_revision, shop_policy_revision, service_name, duration_minutes,
    buffer_minutes, price_krw, deposit_krw, cancellation_notice_minutes, cancellation_policy, deposit_policy,
    deposit_bank_name, deposit_account_number, deposit_account_holder, deposit_due_at,
    idempotency_key, request_hash, created_at
  ) values (
    shop.id, svc.id, 'manual', p_name, p_phone, p_start, finish, occupied_end,
    case when svc.deposit_krw > 0 then 'pending_deposit' else 'confirmed' end,
    case when svc.deposit_krw > 0 then 'awaiting_transfer' else 'not_required' end,
    svc.revision, shop.policy_revision, svc.name, svc.duration_minutes, svc.buffer_minutes,
    svc.price_krw, svc.deposit_krw, shop.cancellation_notice_minutes, shop.cancellation_policy, shop.deposit_policy,
    account.bank_name, account.account_number, account.account_holder,
    case when svc.deposit_krw > 0 then least(p_start, baseline + make_interval(mins => shop.deposit_report_minutes)) end,
    p_key, fingerprint, baseline
  ) returning * into booking;
  insert into public.occupied_slots (shop_id, slot_start, booking_id)
  select shop.id, slot, booking.id from generate_series(p_start, occupied_end - interval '15 min', interval '15 min') slot;
  insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind, actor_user_id, details)
  values (shop.id, booking.id, 'created', p_key, 'owner', shop.owner_user_id, jsonb_build_object('channel', p_channel));
  return booking.id;
exception when unique_violation then
  raise exception using errcode = 'PT409', message = 'r6_time';
end;
$$;

create function public.r6_change(
  p_shop uuid, p_booking uuid, p_revision integer, p_operation text, p_start timestamptz, p_reason text, p_key uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
  baseline timestamptz := clock_timestamp();
  booking public.bookings;
  duration_snapshot public.services;
  past_event public.booking_events;
  payload jsonb;
  event_details jsonb;
  event_name text;
  finish timestamptz;
  occupied_end timestamptz;
begin
  p_reason := nullif(r4_private.clean_text(p_reason), '');
  if p_key is null or p_booking is null or p_revision is null or p_revision < 1
    or p_operation is null or p_operation not in ('move','cancel','complete','no_show')
    or (p_operation = 'move' and not r6_private.on_grid(p_start))
    or (p_operation <> 'move' and p_start is not null)
    or (p_operation = 'cancel' and p_reason is null)
    or char_length(p_reason) > 200 or p_reason ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'r6_input';
  end if;
  payload := jsonb_build_array(p_revision, p_operation, extract(epoch from p_start), p_reason);
  perform r5_private.expire(shop.id, baseline);
  select * into booking from public.bookings b where b.shop_id = shop.id and b.id = p_booking for update;
  if not found then raise exception using errcode = '42501', message = 'r6_missing'; end if;

  select * into past_event from public.booking_events e
  where e.shop_id = shop.id and e.booking_id = booking.id and e.event_key = p_key;
  if found then
    if past_event.actor_kind <> 'owner' or (past_event.details->'request') is distinct from payload then
      raise exception using errcode = 'PT409', message = 'r6_key';
    end if;
    return;
  end if;
  if booking.revision <> p_revision then raise exception using errcode = 'PT409', message = 'r6_stale'; end if;

  event_details := jsonb_build_object('request', payload, 'previous_status', booking.status, 'reason', p_reason);
  if p_operation = 'move' then
    if booking.status not in ('confirmed','pending_deposit') or booking.starts_at <= baseline then
      raise exception using errcode = 'PT409', message = 'r6_state';
    end if;
    if p_start = booking.starts_at then return; end if;
    if booking.deposit_due_at is not null and p_start < booking.deposit_due_at then
      raise exception using errcode = 'PT409', message = 'r6_deadline';
    end if;
    duration_snapshot.duration_minutes := booking.duration_minutes;
    duration_snapshot.buffer_minutes := booking.buffer_minutes;
    shop.min_notice_minutes := 0;
    -- If validation or event insertion fails this deletion rolls back with the RPC.
    delete from public.occupied_slots where shop_id = shop.id and booking_id = booking.id;
    if duration_snapshot.duration_minutes::bigint + duration_snapshot.buffer_minutes > 1440
      or not r5_private.can_book(shop, duration_snapshot, p_start, baseline) then
      raise exception using errcode = 'PT409', message = 'r6_time';
    end if;
    finish := p_start + make_interval(mins => booking.duration_minutes);
    occupied_end := finish + make_interval(mins => booking.buffer_minutes);
    update public.bookings set starts_at = p_start, ends_at = finish, occupied_until = occupied_end
    where shop_id = shop.id and id = booking.id;
    insert into public.occupied_slots (shop_id, slot_start, booking_id)
    select shop.id, slot, booking.id from generate_series(p_start, occupied_end - interval '15 min', interval '15 min') slot;
    event_name := 'rescheduled';
    event_details := event_details || jsonb_build_object('from', booking.starts_at, 'to', p_start);
  elsif p_operation = 'cancel' then
    if booking.status not in ('confirmed','pending_deposit') then
      raise exception using errcode = 'PT409', message = 'r6_state';
    end if;
    update public.bookings set status = 'cancelled',
      money_followup_status = case when booking.deposit_krw > 0 then 'review_needed' else money_followup_status end
    where shop_id = shop.id and id = booking.id;
    delete from public.occupied_slots where shop_id = shop.id and booking_id = booking.id;
    event_name := 'cancelled';
  else
    if booking.status <> 'confirmed' or booking.starts_at > baseline then
      raise exception using errcode = 'PT409', message = 'r6_state';
    end if;
    event_name := case when p_operation = 'complete' then 'completed' else 'no_show' end;
    update public.bookings set status = event_name where shop_id = shop.id and id = booking.id;
  end if;
  insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind, actor_user_id, details)
  values (shop.id, booking.id, event_name, p_key, 'owner', shop.owner_user_id, event_details);
exception when unique_violation then
  raise exception using errcode = 'PT409', message = 'r6_time';
end;
$$;

create function public.r6_block(
  p_shop uuid, p_key uuid, p_start timestamptz, p_end timestamptz, p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
  baseline timestamptz := clock_timestamp();
  existing public.blocks;
begin
  p_reason := r4_private.clean_text(p_reason);
  if p_key is null or not r6_private.on_grid(p_start) or not r6_private.on_grid(p_end)
    or p_end <= p_start or p_end - p_start > interval '744 hours'
    or p_reason is null or char_length(p_reason) not between 1 and 120 or p_reason ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'r6_input';
  end if;
  select * into existing from public.blocks b where b.shop_id = shop.id and b.id = p_key;
  if found then
    if existing.starts_at <> p_start or existing.ends_at <> p_end or existing.reason <> p_reason then
      raise exception using errcode = 'PT409', message = 'r6_key';
    end if;
    return existing.id;
  end if;
  if p_start <= baseline or p_end > baseline + interval '8784 hours' then
    raise exception using errcode = 'PT409', message = 'r6_time';
  end if;
  perform r5_private.expire(shop.id, baseline);
  insert into public.blocks (id, shop_id, starts_at, ends_at, reason) values (p_key, shop.id, p_start, p_end, p_reason);
  insert into public.occupied_slots (shop_id, slot_start, block_id)
  select shop.id, slot, p_key from generate_series(p_start, p_end - interval '15 min', interval '15 min') slot;
  return p_key;
exception when unique_violation then
  raise exception using errcode = 'PT409', message = 'r6_time';
end;
$$;

create function public.r6_unblock(p_shop uuid, p_block uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
  existing public.blocks;
begin
  select * into existing from public.blocks b where b.shop_id = shop.id and b.id = p_block for update;
  if not found then raise exception using errcode = '42501', message = 'r6_missing'; end if;
  if existing.released_at is not null then return; end if;
  update public.blocks set released_at = clock_timestamp() where shop_id = shop.id and id = p_block;
  delete from public.occupied_slots where shop_id = shop.id and block_id = p_block;
end;
$$;

create function public.r6_schedule(p_shop uuid, p_from date, p_until date, p_status text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
  lower_bound timestamptz;
  upper_bound timestamptz;
begin
  if p_from is null or p_until is null or p_from not between date '2000-01-01' and date '2099-12-31'
    or p_until not between date '2000-01-02' and date '2100-01-01'
    or (p_status is not null and p_status not in ('confirmed','pending_deposit','cancelled','expired','completed','no_show')) then
    raise exception using errcode = '22023', message = 'r6_input';
  end if;
  if p_until - p_from not between 1 and 42 then
    raise exception using errcode = '22023', message = 'r6_input';
  end if;
  lower_bound := p_from::timestamp at time zone 'Asia/Seoul';
  upper_bound := p_until::timestamp at time zone 'Asia/Seoul';
  perform r5_private.expire(shop.id, clock_timestamp());
  return (
    with candidates as (
      select id, starts_at, ends_at, occupied_until, service_name, customer_name, status
      from public.bookings where shop_id = shop.id and starts_at < upper_bound and occupied_until > lower_bound
    ), items as (
      select * from candidates where p_status is null or status = p_status order by starts_at, id limit 501
    ), summary as (
      select status,count(*) n from candidates group by status
    ), blocks as (
      select id, starts_at, ends_at, reason from public.blocks
      where shop_id = shop.id and released_at is null and starts_at < upper_bound and ends_at > lower_bound
      order by starts_at,id limit 501
    )
    select jsonb_build_object(
      'bookings', coalesce((select jsonb_agg(to_jsonb(i) order by i.starts_at,i.id) from items i), '[]'::jsonb),
      'blocks', coalesce((select jsonb_agg(to_jsonb(b) order by b.starts_at,b.id) from blocks b), '[]'::jsonb),
      'summary', coalesce((select jsonb_object_agg(status,n) from summary), '{}'::jsonb)
    )
  );
end;
$$;

create function public.r6_detail(p_shop uuid, p_booking uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
begin
  perform r5_private.expire(shop.id, clock_timestamp());
  return (
    select jsonb_build_object(
      'id', b.id, 'revision', b.revision, 'source', b.source, 'customer_name', b.customer_name,
      'customer_phone', b.customer_phone, 'starts_at', b.starts_at, 'ends_at', b.ends_at,
      'status', b.status, 'deposit_status', b.deposit_status, 'money_followup_status', b.money_followup_status,
      'price_krw', b.price_krw, 'deposit_krw', b.deposit_krw, 'deposit_due_at', b.deposit_due_at,
      'service_name', b.service_name, 'duration_minutes', b.duration_minutes, 'buffer_minutes', b.buffer_minutes,
      'cancellation_policy', b.cancellation_policy, 'deposit_policy', b.deposit_policy,
      'events', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', e.id, 'type', e.event_type, 'at', e.created_at,
          'reason', e.details->>'reason', 'from', e.details->>'from', 'to', e.details->>'to', 'channel', e.details->>'channel'
        ) order by e.created_at desc, e.id)
        from (select * from public.booking_events e
          where e.shop_id = shop.id and e.booking_id = b.id order by e.created_at desc,e.id limit 100) e
      ), '[]'::jsonb)
    )
    from public.bookings b where b.shop_id = shop.id and b.id = p_booking
  );
end;
$$;

revoke all on all functions in schema r6_private from public, anon, authenticated, service_role;
revoke all on function
  public.r6_manual(uuid,uuid,integer,integer,timestamptz,text,text,text,uuid),
  public.r6_change(uuid,uuid,integer,text,timestamptz,text,uuid),
  public.r6_block(uuid,uuid,timestamptz,timestamptz,text), public.r6_unblock(uuid,uuid),
  public.r6_schedule(uuid,date,date,text), public.r6_detail(uuid,uuid)
from public, anon, authenticated, service_role;
grant execute on function
  public.r6_manual(uuid,uuid,integer,integer,timestamptz,text,text,text,uuid),
  public.r6_change(uuid,uuid,integer,text,timestamptz,text,uuid),
  public.r6_block(uuid,uuid,timestamptz,timestamptz,text), public.r6_unblock(uuid,uuid),
  public.r6_schedule(uuid,date,date,text), public.r6_detail(uuid,uuid)
to authenticated;
notify pgrst, 'reload schema';
