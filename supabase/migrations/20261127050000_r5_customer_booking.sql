-- Apply the whole file in a single transaction.
create schema r5_private;
revoke all on schema r5_private from public, anon, authenticated, service_role;

create table r5_private.rate_buckets (
  bucket integer primary key,
  minute bigint not null,
  used integer not null
);

create table r5_private.service_requests (
  shop_id uuid not null,
  request_id uuid not null,
  service_id uuid not null,
  request_hash bytea not null,
  primary key (shop_id, request_id),
  foreign key (shop_id, service_id) references public.services (shop_id, id)
);

alter table r5_private.rate_buckets enable row level security;
alter table r5_private.service_requests enable row level security;
revoke all on all tables in schema r5_private from public, anon, authenticated, service_role;

create index r5_booking_deposit_due_idx on public.bookings (shop_id, deposit_due_at)
where status = 'pending_deposit' and deposit_status = 'awaiting_transfer';

create function r5_private.take_bucket(p_bucket integer, p_limit integer)
returns boolean language sql set search_path = '' as $$
  insert into r5_private.rate_buckets as b (bucket, minute, used)
  values (p_bucket, floor(extract(epoch from clock_timestamp()) / 60)::bigint, 1)
  on conflict (bucket) do update
  set minute = greatest(b.minute, excluded.minute),
      used = case when b.minute < excluded.minute then 1 else least(b.used + 1, p_limit + 1) end
  returning used <= p_limit
$$;

-- Fixed bucket counts bound storage even when an attacker invents slugs or addresses.
create function public.r5_allow_request(p_group text, p_slug text, p_client text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  kind integer;
  scoped_limit integer;
  client_limit integer;
begin
  case p_group
    when 'browse' then kind := 0; scoped_limit := 180; client_limit := 45;
    when 'create' then kind := 1; scoped_limit := 30; client_limit := 6;
    when 'confirm' then kind := 2; scoped_limit := 90; client_limit := 24;
    else return false;
  end case;
  if p_slug is null or char_length(p_slug) not between 1 and 60
    or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then return false; end if;
  if not r5_private.take_bucket(kind, scoped_limit * 8) then return false; end if;
  if not r5_private.take_bucket(10 + kind * 1024 + (hashtext(p_slug) & 1023), scoped_limit) then
    return false;
  end if;
  if p_client is not null and p_client ~ '^[a-f0-9]{64}$' then
    return r5_private.take_bucket(4000 + kind * 4096 + (hashtext(p_client) & 4095), client_limit);
  end if;
  return true;
end;
$$;

create function r5_private.valid_token_hash(p_token_hash text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_token_hash ~ '^[a-f0-9]{64}$', false)
$$;

create function r5_private.last_day(p_shop public.shops, p_now timestamptz)
returns date language sql stable set search_path = '' as $$
  select (p_now at time zone 'Asia/Seoul')::date + least(p_shop.booking_window_days, 90) - 1
$$;

create function r5_private.can_book(
  p_shop public.shops, p_service public.services, p_start timestamptz, p_now timestamptz
)
returns boolean language sql stable set search_path = '' as $$
  select p_start > p_now
    and extract(epoch from (p_start - p_now)) >= p_shop.min_notice_minutes::bigint * 60
    and (p_start at time zone 'Asia/Seoul')::date <= r5_private.last_day(p_shop, p_now)
    and p_start = date_bin(interval '15 min', p_start, timestamptz '2000-01-01 00:00+09')
    and not exists (
      select
      from generate_series(
        p_start,
        p_start + make_interval(mins => p_service.duration_minutes + p_service.buffer_minutes - 15),
        interval '15 min'
      ) t(slot)
      cross join lateral (
        select extract(isodow from t.slot at time zone 'Asia/Seoul')::integer as weekday,
          extract(hour from t.slot at time zone 'Asia/Seoul')::integer * 60
            + extract(minute from t.slot at time zone 'Asia/Seoul')::integer as minute
      ) local_time
      where not exists (
        select from public.shop_weekly_periods p
        where p.shop_id = p_shop.id and p.iso_weekday = local_time.weekday
          and p.period_kind = 'opening' and p.start_minute <= local_time.minute
          and p.end_minute >= local_time.minute + 15
      ) or exists (
        select from public.shop_weekly_periods p
        where p.shop_id = p_shop.id and p.iso_weekday = local_time.weekday
          and p.period_kind = 'break' and p.start_minute < local_time.minute + 15
          and p.end_minute > local_time.minute
      ) or exists (
        select
        from public.occupied_slots o
        left join public.bookings b on b.shop_id = o.shop_id and b.id = o.booking_id
        where o.shop_id = p_shop.id and o.slot_start = t.slot
          and (o.block_id is not null or not (
            b.status = 'pending_deposit' and b.deposit_status = 'awaiting_transfer' and b.deposit_due_at <= p_now
          ))
      )
    )
$$;

-- Call only while the owning shop row is locked, before locking individual reservations.
create function r5_private.expire(p_shop_id uuid, p_now timestamptz)
returns void language sql set search_path = '' as $$
  with expired as (
    update public.bookings
    set status = 'expired'
    where shop_id = p_shop_id and status = 'pending_deposit'
      and deposit_status = 'awaiting_transfer' and deposit_due_at <= p_now
    returning id
  ), released as (
    delete from public.occupied_slots o using expired e
    where o.shop_id = p_shop_id and o.booking_id = e.id
  )
  insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind)
  select p_shop_id, id, 'expired', gen_random_uuid(), 'system' from expired
$$;

create function public.r5_catalog(p_slug text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'name', s.name, 'today', (statement_timestamp() at time zone 'Asia/Seoul')::date,
    'lastDay', r5_private.last_day(s, statement_timestamp()),
    'policyRevision', s.policy_revision, 'cancellationPolicy', s.cancellation_policy,
    'depositPolicy', s.deposit_policy, 'reportMinutes', s.deposit_report_minutes,
    'cancellationMinutes', s.cancellation_notice_minutes,
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', v.id, 'name', v.name, 'description', v.description, 'revision', v.revision,
        'duration', v.duration_minutes, 'buffer', v.buffer_minutes, 'price', v.price_krw, 'deposit', v.deposit_krw
      ) order by v.created_at, v.id)
      from (
        select * from public.services
        where shop_id = s.id and is_active and is_public
        order by created_at, id limit 200
      ) v
    ), '[]'::jsonb)
  )
  from public.shops s where s.slug = p_slug
$$;

create function public.r5_slots(p_slug text, p_service uuid, p_day date, p_revision integer, p_policy integer)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  shop public.shops;
  svc public.services;
  baseline timestamptz := statement_timestamp();
  first_slot timestamptz;
begin
  select * into shop from public.shops s where s.slug = p_slug;
  if not found then raise exception using errcode = 'PT404', message = 'r5_missing'; end if;
  select * into svc from public.services s where s.id = p_service and s.shop_id = shop.id and s.is_public and s.is_active;
  if not found or svc.revision is distinct from p_revision or shop.policy_revision is distinct from p_policy then
    raise exception using errcode = 'PT409', message = 'r5_revision';
  end if;
  if p_day is null or not isfinite(p_day) or p_day < (baseline at time zone 'Asia/Seoul')::date
    or p_day > r5_private.last_day(shop, baseline) then
    raise exception using errcode = '22023', message = 'r5_time';
  end if;
  if svc.duration_minutes::bigint + svc.buffer_minutes > 1440 then return '[]'::jsonb; end if;

  first_slot := p_day::timestamp at time zone 'Asia/Seoul';
  return coalesce((
    select jsonb_agg(t.starts order by t.starts)
    from generate_series(first_slot, first_slot + interval '23 hours 45 min', interval '15 min') t(starts)
    where r5_private.can_book(shop, svc, t.starts, baseline)
  ), '[]'::jsonb);
end;
$$;

create function public.r5_create(
  p_slug text, p_service uuid, p_start timestamptz, p_revision integer, p_policy integer,
  p_name text, p_phone text, p_consent text, p_key uuid, p_token_hash text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops;
  svc public.services;
  booking public.bookings;
  account public.shop_bank_accounts;
  shop_id_lookup uuid;
  token_hash bytea;
  request_digest bytea;
  baseline timestamptz;
  finish timestamptz;
  occupied_end timestamptz;
begin
  if not r5_private.valid_token_hash(p_token_hash) or p_key is null or p_service is null
    or p_start is null or p_start < timestamptz '2000-01-01 00:00+00' or p_start >= timestamptz '2100-01-01 00:00+00'
    or p_revision is null or p_policy is null
    or p_slug is null or char_length(p_slug) not between 1 and 60 then
    raise exception using errcode = '22023', message = 'r5_input';
  end if;
  p_name := r4_private.clean_text(p_name);
  p_phone := regexp_replace(coalesce(p_phone, ''), '[ -]', '', 'g');
  if p_name is null or char_length(p_name) not between 1 and 60 or p_name ~ '[[:cntrl:]]'
    or p_phone !~ '^01[016789][0-9]{7,8}$' or p_consent is null or char_length(p_consent) > 40 then
    raise exception using errcode = '22023', message = 'r5_input';
  end if;

  token_hash := decode(p_token_hash, 'hex');
  request_digest := sha256(convert_to(jsonb_build_array(
    p_slug, p_service, extract(epoch from p_start), p_revision, p_policy, p_name, p_phone, p_consent
  )::text, 'UTF8'));
  -- A successful retry survives an edit or reuse of the public slug.
  perform pg_advisory_xact_lock(hashtextextended(p_token_hash, 501));
  select b.shop_id into shop_id_lookup from public.bookings b where b.confirmation_token_hash = token_hash;
  if not found then select s.id into shop_id_lookup from public.shops s where s.slug = p_slug; end if;
  select * into shop from public.shops s where s.id = shop_id_lookup for update;
  if not found then raise exception using errcode = 'PT404', message = 'r5_missing'; end if;

  baseline := clock_timestamp();
  select * into booking from public.bookings b where b.shop_id = shop.id and b.idempotency_key = p_key;
  if found then
    if booking.confirmation_token_hash is distinct from token_hash or booking.request_hash <> request_digest then
      raise exception using errcode = 'PT409', message = 'r5_key';
    end if;
    perform r5_private.expire(shop.id, baseline);
    return jsonb_build_object('created', false);
  end if;
  if shop.slug <> p_slug then raise exception using errcode = 'PT404', message = 'r5_missing'; end if;
  select * into svc from public.services s where s.id = p_service and s.shop_id = shop.id and s.is_public and s.is_active;
  if not found or svc.revision <> p_revision or shop.policy_revision <> p_policy then
    raise exception using errcode = 'PT409', message = 'r5_revision';
  end if;
  if p_consent <> 'r5-privacy-v1' then raise exception using errcode = 'PT409', message = 'r5_revision'; end if;

  perform r5_private.expire(shop.id, baseline);
  if svc.duration_minutes::bigint + svc.buffer_minutes > 1440 or not r5_private.can_book(shop, svc, p_start, baseline) then
    raise exception using errcode = 'PT409', message = 'r5_time';
  end if;
  if svc.deposit_krw > 0 then
    select * into account from public.shop_bank_accounts a where a.shop_id = shop.id;
    if not found or not r4_private.valid_bank(account.bank_name, account.account_number, account.account_holder)
      or r4_private.clean_text(shop.deposit_policy) = '' or r4_private.clean_text(shop.cancellation_policy) = '' then
      raise exception using errcode = 'PT409', message = 'r5_revision';
    end if;
  end if;

  finish := p_start + make_interval(mins => svc.duration_minutes);
  occupied_end := finish + make_interval(mins => svc.buffer_minutes);
  insert into public.bookings (
    shop_id, service_id, source, customer_name, customer_phone, starts_at, ends_at, occupied_until,
    status, deposit_status, service_revision, shop_policy_revision, service_name, duration_minutes,
    buffer_minutes, price_krw, deposit_krw, cancellation_notice_minutes, cancellation_policy, deposit_policy,
    deposit_bank_name, deposit_account_number, deposit_account_holder, deposit_due_at, confirmation_token_hash,
    idempotency_key, request_hash, created_at
  ) values (
    shop.id, svc.id, 'online', p_name, p_phone, p_start, finish, occupied_end,
    case when svc.deposit_krw > 0 then 'pending_deposit' else 'confirmed' end,
    case when svc.deposit_krw > 0 then 'awaiting_transfer' else 'not_required' end,
    svc.revision, shop.policy_revision, svc.name, svc.duration_minutes, svc.buffer_minutes,
    svc.price_krw, svc.deposit_krw, shop.cancellation_notice_minutes, shop.cancellation_policy, shop.deposit_policy,
    account.bank_name, account.account_number, account.account_holder,
    case when svc.deposit_krw > 0 then least(p_start, baseline + make_interval(mins => shop.deposit_report_minutes)) end,
    token_hash, p_key, request_digest, baseline
  ) returning * into booking;
  insert into public.occupied_slots (shop_id, slot_start, booking_id)
  select shop.id, t.slot, booking.id
  from generate_series(p_start, occupied_end - interval '15 min', interval '15 min') t(slot);
  insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind, details)
  values (shop.id, booking.id, 'created', p_key, 'customer', jsonb_build_object('consent_version', p_consent));
  return jsonb_build_object('created', true);
exception when unique_violation then
  raise exception using errcode = 'PT409', message = 'r5_conflict';
end;
$$;

create function public.r5_confirmation(p_token_hash text, p_report boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings;
  shop public.shops;
  baseline timestamptz;
  report_event text;
begin
  if not r5_private.valid_token_hash(p_token_hash) or p_report is null then return null; end if;
  select * into booking from public.bookings b where b.confirmation_token_hash = decode(p_token_hash, 'hex');
  if not found then return null; end if;
  select * into shop from public.shops s where s.id = booking.shop_id for update;
  baseline := clock_timestamp();
  perform r5_private.expire(shop.id, baseline);
  select * into booking from public.bookings b
  where b.shop_id = shop.id and b.confirmation_token_hash = decode(p_token_hash, 'hex') for update;
  if not found then return null; end if;

  if p_report and booking.deposit_status = 'awaiting_transfer' then
    if booking.status = 'pending_deposit' then
      update public.bookings set deposit_status = 'reported'
      where shop_id = shop.id and id = booking.id returning * into booking;
      report_event := 'deposit_reported';
    elsif booking.status in ('expired', 'cancelled') and booking.money_followup_status = 'none' then
      update public.bookings set money_followup_status = 'review_needed'
      where shop_id = shop.id and id = booking.id returning * into booking;
      report_event := 'deposit_reported_late';
    end if;
    if report_event is not null then
      insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind)
      values (shop.id, booking.id, report_event, gen_random_uuid(), 'customer');
    end if;
  end if;

  return jsonb_build_object(
    'shopName', shop.name, 'serviceName', booking.service_name,
    'startsAt', booking.starts_at, 'endsAt', booking.ends_at,
    'status', booking.status, 'depositStatus', booking.deposit_status, 'followup', booking.money_followup_status,
    'price', booking.price_krw, 'deposit', booking.deposit_krw,
    'dueAt', booking.deposit_due_at, 'cancellationPolicy', booking.cancellation_policy, 'depositPolicy', booking.deposit_policy,
    'phoneLast4', right(booking.customer_phone, 4),
    'account', case when booking.status = 'pending_deposit' and booking.deposit_status = 'awaiting_transfer'
      then jsonb_build_object('bank', booking.deposit_bank_name, 'number', booking.deposit_account_number, 'holder', booking.deposit_account_holder)
      else null end
  );
end;
$$;

create function public.r5_create_service(
  p_shop_id uuid, p_request_id uuid, p_name text, p_description text,
  p_duration integer, p_buffer integer, p_price integer, p_deposit integer, p_state text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  stored r5_private.service_requests;
  hashed bytea;
  result uuid;
begin
  perform r4_private.lock_shop(p_shop_id, null);
  if p_request_id is null then raise exception using errcode = '22023', message = 'r4_service_input'; end if;
  hashed := sha256(convert_to(jsonb_build_array(
    p_name, p_description, p_duration, p_buffer, p_price, p_deposit, p_state
  )::text, 'UTF8'));
  select * into stored from r5_private.service_requests r where r.shop_id = p_shop_id and r.request_id = p_request_id;
  if found then
    if stored.request_hash <> hashed then raise exception using errcode = 'PT409', message = 'r5_service_key'; end if;
    return stored.service_id;
  end if;
  result := public.r4_save_service(p_shop_id, null, null, p_name, p_description, p_duration, p_buffer, p_price, p_deposit, p_state);
  insert into r5_private.service_requests values (p_shop_id, p_request_id, result, hashed);
  return result;
end;
$$;

revoke all on all functions in schema r5_private from public, anon, authenticated, service_role;
revoke all on function
  public.r5_allow_request(text,text,text), public.r5_catalog(text), public.r5_slots(text,uuid,date,integer,integer),
  public.r5_create(text,uuid,timestamptz,integer,integer,text,text,text,uuid,text), public.r5_confirmation(text,boolean),
  public.r5_create_service(uuid,uuid,text,text,integer,integer,integer,integer,text)
from public, anon, authenticated, service_role;
grant execute on function
  public.r5_allow_request(text,text,text), public.r5_catalog(text), public.r5_slots(text,uuid,date,integer,integer),
  public.r5_create(text,uuid,timestamptz,integer,integer,text,text,text,uuid,text), public.r5_confirmation(text,boolean)
to service_role;
grant execute on function public.r5_create_service(uuid,uuid,text,text,integer,integer,integer,integer,text)
to authenticated;

notify pgrst, 'reload schema';
