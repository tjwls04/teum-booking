-- Apply in one transaction after R8. Older migrations remain unchanged.
update public.shops set booking_window_days = 90, policy_revision = policy_revision + 1
where booking_window_days > 90;
alter table public.shops add constraint shops_booking_window_public_cap check (booking_window_days <= 90);

create or replace function public.r4_save_policy(
  p_shop_id uuid, p_revision integer, p_notice integer, p_window integer,
  p_cancellation_notice integer, p_report integer, p_cancellation_policy text, p_deposit_policy text,
  p_bank text, p_account_number text, p_account_holder text
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  has_account boolean;
begin
  if p_revision is null then
    raise exception using errcode = '22023', message = 'r4_policy_input';
  end if;
  perform r4_private.lock_shop(p_shop_id, p_revision);

  p_cancellation_policy := coalesce(r4_private.clean_text(p_cancellation_policy), '');
  p_deposit_policy := coalesce(r4_private.clean_text(p_deposit_policy), '');
  p_bank := coalesce(r4_private.clean_text(p_bank), '');
  p_account_number := coalesce(r4_private.clean_text(p_account_number), '');
  p_account_holder := coalesce(r4_private.clean_text(p_account_holder), '');
  has_account := p_bank <> '' or p_account_number <> '' or p_account_holder <> '';

  if p_notice is null or p_notice < 0 or p_window is null or p_window not between 1 and 90
    or p_cancellation_notice is null or p_cancellation_notice < 0 or p_report is null or p_report not in (30, 60, 120)
    or char_length(p_cancellation_policy) > 2000 or char_length(p_deposit_policy) > 2000
  then
    raise exception using errcode = '22023', message = 'r4_policy_input';
  end if;
  if has_account and not r4_private.valid_bank(p_bank, p_account_number, p_account_holder) then
    raise exception using errcode = '22023', message = 'r4_bank_input';
  end if;

  if (not has_account or p_cancellation_policy = '' or p_deposit_policy = '')
    and exists (
      select from public.services s
      where s.shop_id = p_shop_id and s.is_public and s.is_active and s.deposit_krw > 0
    )
  then
    raise exception using errcode = '22023', message = 'r4_deposit_requirements';
  end if;

  if has_account then
    insert into public.shop_bank_accounts (shop_id, bank_name, account_number, account_holder)
    values (p_shop_id, p_bank, p_account_number, p_account_holder)
    on conflict (shop_id) do update
    set bank_name = excluded.bank_name, account_number = excluded.account_number, account_holder = excluded.account_holder;
  else
    delete from public.shop_bank_accounts where shop_id = p_shop_id;
  end if;

  update public.shops
  set min_notice_minutes = p_notice, booking_window_days = p_window,
      cancellation_notice_minutes = p_cancellation_notice, deposit_report_minutes = p_report,
      cancellation_policy = p_cancellation_policy, deposit_policy = p_deposit_policy,
      policy_revision = policy_revision + 1
  where id = p_shop_id;
end;
$$;
-- Preserve service edit callers while routing every new service through the request ledger.
alter function public.r4_save_service(uuid,uuid,integer,text,text,integer,integer,integer,integer,text)
  set schema r4_private;
revoke all on function r4_private.r4_save_service(uuid,uuid,integer,text,text,integer,integer,integer,integer,text)
from public, anon, authenticated, service_role;

create function public.r4_save_service(
  p_shop_id uuid, p_service_id uuid, p_revision integer, p_name text, p_description text,
  p_duration integer, p_buffer integer, p_price integer, p_deposit integer, p_state text
)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if p_service_id is null then
    perform r4_private.lock_shop(p_shop_id, null);
    raise exception using errcode = '22023', message = 'r9_service_request_required';
  end if;
  return r4_private.r4_save_service(p_shop_id, p_service_id, p_revision, p_name, p_description,
    p_duration, p_buffer, p_price, p_deposit, p_state);
end;
$$;

revoke all on function public.r4_save_service(uuid,uuid,integer,text,text,integer,integer,integer,integer,text)
  from public, anon, authenticated, service_role;
grant execute on function public.r4_save_service(uuid,uuid,integer,text,text,integer,integer,integer,integer,text)
  to authenticated;

create or replace function public.r5_create_service(
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
  result := r4_private.r4_save_service(p_shop_id, null, null, p_name, p_description, p_duration, p_buffer, p_price, p_deposit, p_state);
  insert into r5_private.service_requests values (p_shop_id, p_request_id, result, hashed);
  return result;
end;
$$;

-- UUID scopes avoid collisions between shop quotas. Rows are allocated only for existing shops.
create schema r9_private;
revoke all on schema r9_private from public, anon, authenticated, service_role;
create table r9_private.shop_quota (
  shop_id uuid not null references public.shops(id),
  operation smallint not null check (operation between 0 and 3),
  minute bigint not null,
  used integer not null,
  primary key (shop_id, operation)
);
alter table r9_private.shop_quota enable row level security;
revoke all on r9_private.shop_quota from public, anon, authenticated, service_role;

create function public.r9_allow_booking(p_operation text,p_slug text,p_client text,p_token_hash text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  group_id smallint;
  shop_limit integer;
  client_limit integer;
  shop_id_lookup uuid;
  allowed boolean;
begin
  case p_operation
    when 'catalog' then group_id := 0; shop_limit := 180; client_limit := 45;
    when 'slots' then group_id := 0; shop_limit := 180; client_limit := 45;
    when 'create' then group_id := 1; shop_limit := 30; client_limit := 6;
    when 'confirm' then group_id := 2; shop_limit := 90; client_limit := 24;
    when 'report' then group_id := 3; shop_limit := 45; client_limit := 12;
    else return 'missing';
  end case;
  -- A client rejected here cannot debit shop or global capacity.
  if p_client is not null and r5_private.valid_token_hash(p_client)
    and not r5_private.take_bucket(20000 + group_id * 4096 + (hashtext(p_client) & 4095),client_limit)
  then return 'limited'; end if;

  if group_id <> 0 then
    if not r5_private.valid_token_hash(p_token_hash) then return 'missing'; end if;
    select b.shop_id into shop_id_lookup from public.bookings b where b.confirmation_token_hash = decode(p_token_hash,'hex');
  end if;
  -- A previously created booking can still be replayed after the shop changes its slug.
  if shop_id_lookup is null and group_id in (0,1)
    and char_length(p_slug) between 3 and 60 and p_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
  then
    select s.id into shop_id_lookup from public.shops s where s.slug = p_slug;
  end if;
  if shop_id_lookup is null then return 'missing'; end if;

  insert into r9_private.shop_quota as quota (shop_id,operation,minute,used)
  values (shop_id_lookup,group_id,floor(extract(epoch from clock_timestamp()) / 60)::bigint,1)
  on conflict (shop_id,operation) do update
    set minute = greatest(quota.minute,excluded.minute),
        used = case when quota.minute < excluded.minute then 1 else least(quota.used + 1,shop_limit + 1) end
  returning used <= shop_limit into allowed;
  if not allowed or not r5_private.take_bucket(19000 + group_id,shop_limit * 8) then return 'limited'; end if;
  return 'allowed';
end;
$$;

revoke all on function public.r9_allow_booking(text,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.r9_allow_booking(text,text,text,text) to service_role;
notify pgrst, 'reload schema';
