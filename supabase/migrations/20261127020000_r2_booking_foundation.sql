-- Supabase CLI applies the schema and migration history in one transaction.
create table public.shops (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references auth.users (id),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (btrim(name) <> ''),
  time_zone text not null default 'Asia/Seoul' check (time_zone = 'Asia/Seoul'),
  policy_revision integer not null default 1 check (policy_revision > 0),
  min_notice_minutes integer not null default 120 check (min_notice_minutes >= 0),
  booking_window_days integer not null default 60 check (booking_window_days > 0),
  cancellation_notice_minutes integer not null default 0 check (cancellation_notice_minutes >= 0),
  deposit_report_minutes integer not null default 60 check (deposit_report_minutes in (30, 60, 120)),
  cancellation_policy text not null default '',
  deposit_policy text not null default '',
  created_at timestamptz not null default now()
);

-- Recurring local wall-clock periods: ISO weekdays (Monday=1), minutes since Seoul midnight.
-- Split overnight hours at midnight. A day without rows is closed.
create table public.shop_weekly_periods (
  shop_id uuid not null references public.shops (id),
  iso_weekday smallint not null check (iso_weekday between 1 and 7),
  period_kind text not null check (period_kind in ('opening', 'break')),
  start_minute smallint not null check (start_minute between 0 and 1439 and start_minute % 15 = 0),
  end_minute smallint not null check (end_minute between 1 and 1440 and end_minute % 15 = 0),
  primary key (shop_id, iso_weekday, period_kind, start_minute),
  check (end_minute > start_minute)
);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  name text not null check (btrim(name) <> ''),
  description text not null default '',
  duration_minutes integer not null check (duration_minutes > 0 and duration_minutes % 15 = 0),
  buffer_minutes integer not null default 0 check (buffer_minutes >= 0 and buffer_minutes % 15 = 0),
  price_krw integer not null check (price_krw >= 0),
  deposit_krw integer not null default 0 check (deposit_krw between 0 and price_krw),
  is_active boolean not null default true,
  is_public boolean not null default false check (not is_public or is_active),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  unique (shop_id, id)
);

create table public.shop_bank_accounts (
  shop_id uuid primary key references public.shops (id),
  bank_name text not null check (btrim(bank_name) <> ''),
  account_number text not null check (btrim(account_number) <> ''),
  account_holder text not null check (btrim(account_holder) <> '')
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  service_id uuid not null,
  source text not null check (source in ('online', 'manual')),
  customer_name text not null check (btrim(customer_name) <> ''),
  customer_phone text not null check (btrim(customer_phone) <> ''),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  occupied_until timestamptz not null,
  status text not null check (status in ('pending_deposit', 'confirmed', 'completed', 'no_show', 'cancelled', 'expired')),
  deposit_status text not null check (deposit_status in ('not_required', 'awaiting_transfer', 'reported', 'verified')),
  money_followup_status text not null default 'none'
    check (money_followup_status in ('none', 'review_needed', 'resolved_recorded')),
  service_revision integer not null check (service_revision > 0),
  shop_policy_revision integer not null check (shop_policy_revision > 0),
  service_name text not null check (btrim(service_name) <> ''),
  duration_minutes integer not null check (duration_minutes > 0 and duration_minutes % 15 = 0),
  buffer_minutes integer not null check (buffer_minutes >= 0 and buffer_minutes % 15 = 0),
  price_krw integer not null check (price_krw >= 0),
  deposit_krw integer not null check (deposit_krw between 0 and price_krw),
  cancellation_notice_minutes integer not null check (cancellation_notice_minutes >= 0),
  cancellation_policy text not null,
  deposit_policy text not null,
  deposit_bank_name text,
  deposit_account_number text,
  deposit_account_holder text,
  deposit_due_at timestamptz,
  deposit_verified_at timestamptz,
  deposit_verified_by uuid references auth.users (id),
  confirmation_token_hash bytea unique check (octet_length(confirmation_token_hash) = 32),
  idempotency_key uuid not null,
  request_hash bytea not null check (octet_length(request_hash) = 32),
  created_at timestamptz not null default now(),
  foreign key (shop_id, service_id) references public.services (shop_id, id),
  unique (shop_id, id),
  unique (shop_id, idempotency_key),
  check (source = 'manual' or confirmation_token_hash is not null),
  check (
    isfinite(starts_at) and isfinite(ends_at) and isfinite(occupied_until)
    and starts_at = date_bin(interval '15 minutes', starts_at, timestamptz '2000-01-01 00:00:00+09')
    and extract(epoch from (ends_at - starts_at)) = duration_minutes::bigint * 60
    and extract(epoch from (occupied_until - ends_at)) = buffer_minutes::bigint * 60
  ),
  check (
    (
      deposit_krw = 0 and deposit_status = 'not_required'
      and status in ('confirmed', 'completed', 'no_show', 'cancelled')
      and deposit_due_at is null and deposit_bank_name is null
      and deposit_account_number is null and deposit_account_holder is null
    ) or (
      deposit_krw > 0
      and (
        (status = 'pending_deposit' and deposit_status in ('awaiting_transfer', 'reported'))
        or (status in ('confirmed', 'completed', 'no_show') and deposit_status = 'verified')
        or (status = 'cancelled' and deposit_status in ('awaiting_transfer', 'reported', 'verified'))
        or (status = 'expired' and deposit_status in ('awaiting_transfer', 'verified'))
      )
      and deposit_due_at is not null and deposit_due_at >= created_at and deposit_due_at <= starts_at
      and nullif(btrim(deposit_bank_name), '') is not null
      and nullif(btrim(deposit_account_number), '') is not null
      and nullif(btrim(deposit_account_holder), '') is not null
    )
  ),
  check (
    (deposit_status = 'verified' and deposit_verified_by is not null
      and deposit_verified_at is not null and isfinite(deposit_verified_at)
      and deposit_verified_at >= created_at)
    or (deposit_status <> 'verified' and deposit_verified_by is null and deposit_verified_at is null)
  ),
  check (
    money_followup_status = 'none'
    or (deposit_krw > 0 and status in ('cancelled', 'expired'))
  ),
  check (
    status not in ('cancelled', 'expired') or deposit_status not in ('reported', 'verified')
    or money_followup_status in ('review_needed', 'resolved_recorded')
  )
);

create index bookings_shop_start_idx on public.bookings (shop_id, starts_at);
create index bookings_shop_service_idx on public.bookings (shop_id, service_id);

create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null default '',
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  check (
    isfinite(starts_at) and isfinite(ends_at) and ends_at > starts_at
    and starts_at = date_bin(interval '15 minutes', starts_at, timestamptz '2000-01-01 00:00:00+09')
    and ends_at = date_bin(interval '15 minutes', ends_at, timestamptz '2000-01-01 00:00:00+09')
  )
);

create index blocks_shop_start_idx on public.blocks (shop_id, starts_at);

-- The PK arbitrates collisions between both sources of bookings and blocks.
-- Later RPCs must write every slot in the half-open interval in one transaction.
create table public.occupied_slots (
  shop_id uuid not null,
  slot_start timestamptz not null check (
    isfinite(slot_start)
    and slot_start = date_bin(interval '15 minutes', slot_start, timestamptz '2000-01-01 00:00:00+09')
  ),
  booking_id uuid,
  block_id uuid,
  primary key (shop_id, slot_start),
  check (num_nonnulls(booking_id, block_id) = 1),
  foreign key (shop_id, booking_id) references public.bookings (shop_id, id),
  foreign key (shop_id, block_id) references public.blocks (shop_id, id)
);

create index occupied_slots_booking_idx on public.occupied_slots (shop_id, booking_id) where booking_id is not null;
create index occupied_slots_block_idx on public.occupied_slots (shop_id, block_id) where block_id is not null;

create table public.booking_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  booking_id uuid not null,
  event_type text not null check (btrim(event_type) <> ''),
  event_key uuid not null,
  actor_kind text not null check (actor_kind in ('owner', 'customer', 'system')),
  actor_user_id uuid references auth.users (id),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  foreign key (shop_id, booking_id) references public.bookings (shop_id, id),
  unique (shop_id, booking_id, event_key),
  check ((actor_kind = 'owner') = (actor_user_id is not null))
);

alter table public.shops enable row level security;
alter table public.shop_weekly_periods enable row level security;
alter table public.services enable row level security;
alter table public.shop_bank_accounts enable row level security;
alter table public.bookings enable row level security;
alter table public.blocks enable row level security;
alter table public.occupied_slots enable row level security;
alter table public.booking_events enable row level security;

-- Override grants inherited from Supabase's public-schema defaults at table creation.
revoke all privileges on table
  public.shops, public.shop_weekly_periods, public.services, public.shop_bank_accounts,
  public.bookings, public.blocks, public.occupied_slots, public.booking_events
from public, anon, authenticated, service_role;

grant select on table
  public.shops, public.shop_weekly_periods, public.services, public.shop_bank_accounts,
  public.blocks, public.occupied_slots
to authenticated;

grant select (
  id, shop_id, service_id, source, customer_name, customer_phone, starts_at, ends_at, occupied_until,
  status, deposit_status, money_followup_status, service_revision, shop_policy_revision,
  service_name, duration_minutes, buffer_minutes, price_krw, deposit_krw, cancellation_notice_minutes,
  cancellation_policy, deposit_policy, deposit_due_at, deposit_verified_at, deposit_verified_by, created_at
) on public.bookings to authenticated;

grant select (
  id, shop_id, booking_id, event_type, actor_kind, actor_user_id, created_at
) on public.booking_events to authenticated;

grant select on table
  public.shops, public.shop_weekly_periods, public.services, public.shop_bank_accounts,
  public.bookings, public.blocks, public.occupied_slots, public.booking_events
to service_role;

create policy shops_select_owner on public.shops
  for select to authenticated using (
    owner_user_id = (select auth.uid())
    and (select auth.jwt() ->> 'is_anonymous') = 'false'
  );

-- The shops policy already filters the visible shop IDs to the caller's own shop.
create policy shop_weekly_periods_select_owner on public.shop_weekly_periods
  for select to authenticated using (shop_id in (select id from public.shops));

create policy services_select_owner on public.services
  for select to authenticated using (shop_id in (select id from public.shops));

create policy shop_bank_accounts_select_owner on public.shop_bank_accounts
  for select to authenticated using (shop_id in (select id from public.shops));

create policy bookings_select_owner on public.bookings
  for select to authenticated using (shop_id in (select id from public.shops));

create policy blocks_select_owner on public.blocks
  for select to authenticated using (shop_id in (select id from public.shops));

create policy occupied_slots_select_owner on public.occupied_slots
  for select to authenticated using (shop_id in (select id from public.shops));

create policy booking_events_select_owner on public.booking_events
  for select to authenticated using (shop_id in (select id from public.shops));
