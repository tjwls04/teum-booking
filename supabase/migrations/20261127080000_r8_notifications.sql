-- Apply in one transaction. Configure the worker schedule separately.
create schema r8_private;
revoke all on schema r8_private from public, anon, authenticated, service_role;

create table r8_private.inbox (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  booking_id uuid not null,
  kind text not null check (kind in ('created','deposit_reported','expired','deposit_reported_late','deposit_delayed','today')),
  dedupe_key text not null,
  created_at timestamptz not null default clock_timestamp(),
  read_at timestamptz,
  push_until timestamptz not null,
  foreign key (shop_id,booking_id) references public.bookings (shop_id,id),
  unique (shop_id,dedupe_key),
  unique (shop_id,id)
);
create index r8_inbox_recent on r8_private.inbox (shop_id,created_at desc,id desc);
create index r8_inbox_unread on r8_private.inbox (shop_id,created_at) where read_at is null;

create table r8_private.settings (
  shop_id uuid primary key references public.shops (id),
  enabled boolean not null,
  changed_at timestamptz not null default clock_timestamp()
);
create table r8_private.devices (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  endpoint text unique,
  p256dh text,
  auth_secret text,
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id,id),
  check (num_nonnulls(endpoint,p256dh,auth_secret) in (0,3))
);
create index r8_active_devices on r8_private.devices (shop_id) where endpoint is not null;

create table r8_private.jobs (
  notification_id uuid primary key,
  shop_id uuid not null,
  created_at timestamptz not null,
  expanded_at timestamptz,
  foreign key (shop_id,notification_id) references r8_private.inbox (shop_id,id),
  unique (shop_id,notification_id)
);
create index r8_jobs_pending on r8_private.jobs (created_at,notification_id) where expanded_at is null;

create table r8_private.deliveries (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  notification_id uuid not null,
  device_id uuid not null,
  status text not null default 'pending' check (status in ('pending','sent','failed','skipped')),
  attempts integer not null default 0 check (attempts between 0 and 5),
  next_at timestamptz not null,
  lease_token uuid,
  lease_until timestamptz,
  last_error text,
  finished_at timestamptz,
  unique (notification_id,device_id),
  foreign key (shop_id,notification_id) references r8_private.jobs (shop_id,notification_id),
  foreign key (shop_id,device_id) references r8_private.devices (shop_id,id),
  check (num_nonnulls(lease_token,lease_until) in (0,2)),
  check ((status = 'pending') = (finished_at is null))
);
create index r8_deliveries_ready on r8_private.deliveries (next_at,id) where status = 'pending';

alter table r8_private.inbox enable row level security;
alter table r8_private.settings enable row level security;
alter table r8_private.devices enable row level security;
alter table r8_private.jobs enable row level security;
alter table r8_private.deliveries enable row level security;
revoke all on all tables in schema r8_private from public, anon, authenticated, service_role;

create function r8_private.emit(p_shop uuid,p_booking uuid,p_kind text,p_key text,p_until timestamptz)
returns void language sql set search_path = '' as $$
  with notification as (
    insert into r8_private.inbox (shop_id,booking_id,kind,dedupe_key,push_until)
    values (p_shop,p_booking,p_kind,p_key,p_until)
    on conflict (shop_id,dedupe_key) do nothing returning id,shop_id,created_at
  )
  insert into r8_private.jobs (notification_id,shop_id,created_at)
  select id,shop_id,created_at from notification
$$;

create function r8_private.on_booking_event()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.event_type in ('created','deposit_reported','expired','deposit_reported_late') then
    perform r8_private.emit(new.shop_id,new.booking_id,new.event_type,'event:' || new.id,
      clock_timestamp() + interval '24 hours');
  end if;
  return new;
end;
$$;

create trigger r8_booking_event after insert on public.booking_events
for each row execute function r8_private.on_booking_event();

create index r8_today_bookings on public.bookings (starts_at,id) where status in ('pending_deposit','confirmed');
create index r8_delayed_deposits on public.bookings (deposit_due_at,id)
where status = 'pending_deposit' and deposit_status = 'reported';

create function r8_private.scan(observed_at timestamptz,p_shop uuid default null)
returns void language plpgsql set search_path = '' as $$
declare
  seoul_day timestamp := date_trunc('day',observed_at at time zone 'Asia/Seoul');
  day_start timestamptz := seoul_day at time zone 'Asia/Seoul';
  day_end timestamptz := (seoul_day + interval '1 day') at time zone 'Asia/Seoul';
  day_key text := 'today:' || to_char(seoul_day,'YYYY-MM-DD') || ':';
  target record;
begin
  for target in
    select b.shop_id,b.id from public.bookings b
    where (p_shop is null or b.shop_id = p_shop) and b.status = 'pending_deposit' and b.deposit_status = 'reported' and b.deposit_due_at <= observed_at
      and not exists (select from r8_private.inbox n where n.shop_id = b.shop_id and n.dedupe_key = 'delayed:' || b.id)
    order by b.deposit_due_at,b.id limit 100 for share of b skip locked
  loop
    perform r8_private.emit(target.shop_id,target.id,'deposit_delayed','delayed:' || target.id,observed_at + interval '24 hours');
  end loop;
  for target in
    select b.shop_id,b.id,b.starts_at from public.bookings b
    where (p_shop is null or b.shop_id = p_shop) and b.status in ('pending_deposit','confirmed') and b.starts_at >= day_start and b.starts_at < day_end
      and b.starts_at > observed_at
      and observed_at >= least(day_start + interval '8 hours',b.starts_at - interval '1 hour')
      and (b.status = 'confirmed' or b.deposit_status = 'reported' or b.deposit_due_at > observed_at)
      and not exists (select from r8_private.inbox n where n.shop_id = b.shop_id and n.dedupe_key = day_key || b.id)
    order by b.starts_at,b.id limit 100 for share of b skip locked
  loop
    perform r8_private.emit(target.shop_id,target.id,'today',day_key || target.id,target.starts_at);
  end loop;
end;
$$;

create function public.r8_scan()
returns void language sql security definer set search_path = '' as $$
  select r8_private.scan(statement_timestamp())
$$;

create function r8_private.require_shop(p_shop uuid)
returns void language plpgsql set search_path = '' as $$
declare
  owner_id uuid := r4_private.business_user_id();
begin
  if not exists (select from public.shops s where s.id = p_shop and s.owner_user_id = owner_id) then
    raise exception using errcode = '42501', message = 'r8_owner';
  end if;
end;
$$;

create function public.r8_unread(p_shop uuid)
returns integer language plpgsql stable security definer set search_path = '' as $$
begin
  perform r8_private.require_shop(p_shop);
  return (select count(*)::integer from r8_private.inbox where shop_id = p_shop and read_at is null);
end;
$$;

create function public.r8_inbox(p_shop uuid,p_unread boolean,p_before timestamptz,p_before_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform r8_private.require_shop(p_shop);
  if p_unread is null or num_nonnulls(p_before,p_before_id) not in (0,2) then
    raise exception using errcode = '22023', message = 'r8_input';
  end if;
  return coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc,n.id desc) from (
    select id,booking_id,kind,created_at,read_at from r8_private.inbox
    where shop_id = p_shop and (not p_unread or read_at is null)
      and (p_before is null or (created_at,id) < (p_before,p_before_id))
    order by created_at desc,id desc limit 31
  ) n),'[]'::jsonb);
end;
$$;

create function public.r8_target(p_shop uuid,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform r8_private.require_shop(p_shop);
  return (select jsonb_build_object('booking_id',booking_id,'kind',kind) from r8_private.inbox
    where shop_id = p_shop and id = p_id);
end;
$$;

create function public.r8_read(p_shop uuid,p_id uuid,p_read boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform r8_private.require_shop(p_shop);
  if p_read is null or (p_id is null and not p_read) then
    raise exception using errcode = '22023', message = 'r8_input';
  end if;
  update r8_private.inbox set read_at = case when p_read then statement_timestamp() end
  where shop_id = p_shop and (p_id is null or id = p_id) and (read_at is null) = p_read;
end;
$$;

create function public.r8_preferences(p_shop uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform r8_private.require_shop(p_shop);
  return jsonb_build_object(
    'enabled',coalesce((select enabled from r8_private.settings where shop_id = p_shop),true),
    'devices',coalesce((select jsonb_agg(jsonb_build_object('id',id,'created_at',created_at) order by created_at desc)
      from r8_private.devices where shop_id = p_shop and endpoint is not null),'[]'::jsonb)
  );
end;
$$;

create function public.r8_set_enabled(p_shop uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform r8_private.require_shop(p_shop);
  if p_enabled is null then raise exception using errcode = '22023', message = 'r8_input'; end if;
  insert into r8_private.settings (shop_id,enabled) values (p_shop,p_enabled)
  on conflict (shop_id) do update set enabled = excluded.enabled,changed_at = clock_timestamp()
    where settings.enabled is distinct from excluded.enabled;
end;
$$;

create function r8_private.valid_endpoint(p_url text)
returns boolean language sql immutable strict set search_path = '' as $$
  select length(p_url) <= 1600 and p_url collate "C" ~
    '^https://(fcm\.googleapis\.com/fcm/send/|updates\.push\.services\.mozilla\.com/wpush/v[12]/|([a-z0-9-]+\.)+push\.apple\.com/)[A-Za-z0-9_~:.-]{8,}$'
$$;

create function public.r8_register(p_shop uuid,p_endpoint text,p_p256dh text,p_auth text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  device r8_private.devices;
begin
  perform r8_private.require_shop(p_shop);
  if r8_private.valid_endpoint(p_endpoint) is distinct from true
    or p_p256dh is null or p_p256dh collate "C" !~ '^B[A-Za-z0-9_-]{86}$'
    or p_auth is null or p_auth collate "C" !~ '^[A-Za-z0-9_-]{22}$' then
    raise exception using errcode = '22023', message = 'r8_input';
  end if;
  -- Serialize device registration per shop, including the active-device cap.
  perform pg_advisory_xact_lock(hashtextextended('r8-device:' || p_shop,0));
  select * into device from r8_private.devices where endpoint = p_endpoint and shop_id = p_shop for update;
  if found then
    if device.p256dh = p_p256dh and device.auth_secret = p_auth then return; end if;
    update r8_private.devices set endpoint = null,p256dh = null,auth_secret = null where id = device.id;
  elsif (select count(*) from r8_private.devices where shop_id = p_shop and endpoint is not null) >= 10 then
    raise exception using errcode = 'PT409', message = 'r8_device_limit';
  end if;
  insert into r8_private.devices (shop_id,endpoint,p256dh,auth_secret) values (p_shop,p_endpoint,p_p256dh,p_auth)
  on conflict (endpoint) do nothing;
  if not found then raise exception using errcode = 'PT409', message = 'r8_device_conflict'; end if;
end;
$$;

create function public.r8_remove(p_shop uuid,p_id uuid,p_endpoint text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform r8_private.require_shop(p_shop);
  if num_nonnulls(p_id,p_endpoint) <> 1 or (p_endpoint is not null and not r8_private.valid_endpoint(p_endpoint)) then
    raise exception using errcode = '22023', message = 'r8_input';
  end if;
  update r8_private.devices set endpoint = null,p256dh = null,auth_secret = null
  where shop_id = p_shop and endpoint is not null and (id = p_id or endpoint = p_endpoint);
end;
$$;

create function r8_private.claim(p_shop uuid default null)
returns jsonb language plpgsql set search_path = '' as $$
declare
  observed_at timestamptz := statement_timestamp();
  batch jsonb;
begin
  with pending as (
    select j.notification_id from r8_private.jobs j where j.expanded_at is null and (p_shop is null or j.shop_id = p_shop)
    order by j.created_at,j.notification_id limit 100 for update skip locked
  ), expanded as (
    update r8_private.jobs j set expanded_at = observed_at from pending p
    where j.notification_id = p.notification_id returning j.*
  )
  insert into r8_private.deliveries (shop_id,notification_id,device_id,next_at)
  select j.shop_id,j.notification_id,d.id,observed_at from expanded j
  join r8_private.inbox n on (n.shop_id,n.id) = (j.shop_id,j.notification_id)
  join r8_private.devices d on d.shop_id = j.shop_id and d.endpoint is not null and d.created_at <= j.created_at
  left join r8_private.settings s on s.shop_id = j.shop_id
  where n.push_until > observed_at and coalesce(s.enabled and s.changed_at <= n.created_at,true)
  on conflict (notification_id,device_id) do nothing;

  with unavailable as (
    select d.id,d.attempts,n.push_until,device.endpoint,coalesce(s.enabled and s.changed_at <= n.created_at,true) as enabled
    from r8_private.deliveries d
    join r8_private.inbox n on (n.shop_id,n.id) = (d.shop_id,d.notification_id)
    join r8_private.devices device on (device.shop_id,device.id) = (d.shop_id,d.device_id)
    left join r8_private.settings s on s.shop_id = d.shop_id
    where (p_shop is null or d.shop_id = p_shop) and d.status = 'pending' and (d.lease_until is null or d.lease_until <= observed_at)
      and (d.attempts = 5 or n.push_until <= observed_at or device.endpoint is null or not coalesce(s.enabled and s.changed_at <= n.created_at,true))
    order by d.next_at,d.id limit 200 for update of d skip locked
  )
  update r8_private.deliveries d set
    status = case when u.attempts = 5 then 'failed' else 'skipped' end,
    last_error = case when u.attempts = 5 then 'lease_exhausted' when u.endpoint is null then 'device_inactive'
      when not u.enabled then 'disabled' else 'past_deadline' end,
    lease_token = null,lease_until = null,finished_at = observed_at
  from unavailable u where d.id = u.id;

  with ready as (
    select d.id,n.id as notification_id,n.kind,device.endpoint,device.p256dh,device.auth_secret
    from r8_private.deliveries d
    join r8_private.inbox n on (n.shop_id,n.id) = (d.shop_id,d.notification_id)
    join r8_private.devices device on (device.shop_id,device.id) = (d.shop_id,d.device_id)
    left join r8_private.settings s on s.shop_id = d.shop_id
    where (p_shop is null or d.shop_id = p_shop) and d.status = 'pending' and d.next_at <= observed_at and d.attempts < 5
      and (d.lease_until is null or d.lease_until <= observed_at) and n.push_until > observed_at
      and device.endpoint is not null and coalesce(s.enabled and s.changed_at <= n.created_at,true)
    order by d.next_at,d.id limit 24 for update of d skip locked
  ), leased as (
    update r8_private.deliveries d set attempts = d.attempts + 1,
      lease_token = gen_random_uuid(),lease_until = observed_at + interval '90 seconds'
    from ready r where d.id = r.id
    returning d.id,d.lease_token,r.notification_id,r.kind,r.endpoint,r.p256dh,r.auth_secret
  ) select coalesce(jsonb_agg(to_jsonb(leased)),'[]'::jsonb) into batch from leased;
  return batch;
end;
$$;

create function public.r8_claim()
returns jsonb language sql security definer set search_path = '' as $$
  select r8_private.claim()
$$;

create function public.r8_finish(p_id uuid,p_lease uuid,p_result text,p_error text,p_retry_seconds integer)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  delivery r8_private.deliveries;
  observed_at timestamptz := statement_timestamp();
  retry boolean;
begin
  if p_result is null or p_result not in ('sent','retry','failed','gone')
    or (p_result = 'sent') <> (p_error is null)
    or (p_error is not null and p_error collate "C" !~ '^(http_[1-5][0-9]{2}|network|invalid_subscription|blocked_address)$')
    or (p_retry_seconds is not null and (p_result <> 'retry' or p_retry_seconds not between 0 and 3600)) then
    raise exception using errcode = '22023', message = 'r8_input';
  end if;
  select * into delivery from r8_private.deliveries
  where id = p_id and lease_token = p_lease and status = 'pending' and lease_until > observed_at for update;
  if not found then return false; end if;
  retry := p_result = 'retry' and delivery.attempts < 5;
  update r8_private.deliveries set
    status = case when retry then 'pending' when p_result = 'sent' then 'sent' else 'failed' end,
    finished_at = case when not retry then observed_at end,
    next_at = case when retry then observed_at + make_interval(secs => greatest(60 * (1 << (delivery.attempts - 1)),p_retry_seconds)) else next_at end,
    lease_token = null,lease_until = null,last_error = p_error
  where id = delivery.id;
  if p_result = 'gone' then
    update r8_private.devices set endpoint = null,p256dh = null,auth_secret = null
    where shop_id = delivery.shop_id and id = delivery.device_id;
  end if;
  return true;
end;
$$;

revoke all on all functions in schema r8_private from public, anon, authenticated, service_role;
revoke all on function public.r8_unread(uuid),public.r8_inbox(uuid,boolean,timestamptz,uuid),public.r8_target(uuid,uuid),public.r8_read(uuid,uuid,boolean),
  public.r8_preferences(uuid),public.r8_set_enabled(uuid,boolean),public.r8_register(uuid,text,text,text),public.r8_remove(uuid,uuid,text),
  public.r8_scan(),public.r8_claim(),public.r8_finish(uuid,uuid,text,text,integer) from public, anon, authenticated, service_role;
grant execute on function public.r8_unread(uuid),public.r8_inbox(uuid,boolean,timestamptz,uuid),public.r8_target(uuid,uuid),public.r8_read(uuid,uuid,boolean),
  public.r8_preferences(uuid),public.r8_set_enabled(uuid,boolean),public.r8_register(uuid,text,text,text),public.r8_remove(uuid,uuid,text) to authenticated;
grant execute on function public.r8_scan(),public.r8_claim(),public.r8_finish(uuid,uuid,text,text,integer) to service_role;
