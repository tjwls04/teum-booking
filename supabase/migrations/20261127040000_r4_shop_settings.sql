create schema r4_private;
revoke all on schema r4_private from public, anon, authenticated, service_role;

create function r4_private.business_user_id()
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  user_id uuid := auth.uid();
begin
  if user_id is null
    or (auth.jwt() ->> 'is_anonymous') is distinct from 'false'
    or not exists (
      select from auth.users u
      where u.id = user_id and u.email_confirmed_at is not null and nullif(u.email, '') is not null
    )
  then
    raise exception using errcode = '42501', message = 'r4_owner';
  end if;
  return user_id;
end;
$$;

create function r4_private.lock_shop(p_shop_id uuid, p_revision integer)
returns public.shops
language plpgsql
set search_path = ''
as $$
declare
  user_id uuid := r4_private.business_user_id();
  owned_shop public.shops;
begin
  select * into owned_shop
  from public.shops s
  where s.id = p_shop_id and s.owner_user_id = user_id
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'r4_owner';
  end if;
  if p_revision is not null and owned_shop.policy_revision <> p_revision then
    raise exception using errcode = 'PT409', message = 'r4_stale';
  end if;
  return owned_shop;
end;
$$;

create function r4_private.clean_text(value text)
returns text
language sql immutable strict
set search_path = ''
as $$
  select regexp_replace(value, '^[[:space:]]+|[[:space:]]+$', '', 'g')
$$;

create function r4_private.valid_bank(p_bank text, p_number text, p_holder text)
returns boolean
language sql immutable
set search_path = ''
as $$
  select coalesce(
    char_length(r4_private.clean_text(p_bank)) between 1 and 60
    and char_length(r4_private.clean_text(p_holder)) between 1 and 60
    and char_length(r4_private.clean_text(p_number)) <= 40
    and r4_private.clean_text(p_number) ~ '^[0-9]+(-[0-9]+)*$'
    and char_length(replace(r4_private.clean_text(p_number), '-', '')) between 5 and 24,
    false
  )
$$;

revoke all on all functions in schema r4_private from public, anon, authenticated, service_role;

create function public.r4_save_shop(p_shop_id uuid, p_revision integer, p_name text, p_slug text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  user_id uuid := r4_private.business_user_id();
  saved_id uuid;
  constraint_id text;
begin
  p_name := r4_private.clean_text(p_name);
  p_slug := lower(r4_private.clean_text(p_slug));
  if p_name is null or char_length(p_name) not between 1 and 80
    or p_slug is null or char_length(p_slug) not between 3 and 60
    or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    or (p_shop_id is null) <> (p_revision is null)
  then
    raise exception using errcode = '22023', message = 'r4_shop_input';
  end if;

  if p_shop_id is null then
    select s.id into saved_id from public.shops s where s.owner_user_id = user_id;
    if found then return saved_id; end if;

    insert into public.shops (owner_user_id, name, slug)
    values (user_id, p_name, p_slug)
    on conflict (owner_user_id) do nothing
    returning id into saved_id;
    if saved_id is null then
      select s.id into saved_id from public.shops s where s.owner_user_id = user_id;
    end if;
    return saved_id;
  end if;

  perform r4_private.lock_shop(p_shop_id, p_revision);
  update public.shops
  set name = p_name, slug = p_slug, policy_revision = policy_revision + 1
  where id = p_shop_id and owner_user_id = user_id;
  return p_shop_id;
exception when unique_violation then
  get stacked diagnostics constraint_id = constraint_name;
  if constraint_id = 'shops_slug_key' then
    -- A concurrent first registration may have committed with the same slug.
    if p_shop_id is null then
      select s.id into saved_id from public.shops s where s.owner_user_id = user_id;
      if found then return saved_id; end if;
    end if;
    raise exception using errcode = 'PT409', message = 'r4_slug_taken';
  end if;
  raise;
end;
$$;

create function public.r4_save_service(
  p_shop_id uuid, p_service_id uuid, p_revision integer, p_name text, p_description text,
  p_duration integer, p_buffer integer, p_price integer, p_deposit integer, p_state text
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  owned_shop public.shops := r4_private.lock_shop(p_shop_id, null);
  saved_id uuid;
  current_revision integer;
begin
  p_name := r4_private.clean_text(p_name);
  p_description := coalesce(r4_private.clean_text(p_description), '');
  if p_name is null or char_length(p_name) not between 1 and 80 or char_length(p_description) > 1000
    or p_duration is null or p_duration not between 15 and 1440 or p_duration % 15 <> 0
    or p_buffer is null or p_buffer not between 0 and 1440 or p_buffer % 15 <> 0
    or p_duration::bigint + p_buffer > 1440
    or p_price is null or p_price < 0 or p_deposit is null or p_deposit not between 0 and p_price
    or p_state is null or p_state not in ('private', 'public', 'inactive')
    or (p_service_id is null) <> (p_revision is null)
  then
    raise exception using errcode = '22023', message = 'r4_service_input';
  end if;

  if p_service_id is not null then
    select s.revision into current_revision
    from public.services s where s.shop_id = owned_shop.id and s.id = p_service_id;
    if not found then
      raise exception using errcode = '42501', message = 'r4_owner';
    end if;
    if current_revision <> p_revision then
      raise exception using errcode = 'PT409', message = 'r4_stale';
    end if;
  end if;

  if p_state = 'public' and p_deposit > 0 and (
    r4_private.clean_text(owned_shop.deposit_policy) = '' or r4_private.clean_text(owned_shop.cancellation_policy) = ''
    or not exists (
      select from public.shop_bank_accounts a where a.shop_id = owned_shop.id
        and r4_private.valid_bank(a.bank_name, a.account_number, a.account_holder)
    )
  ) then
    raise exception using errcode = '22023', message = 'r4_deposit_requirements';
  end if;

  if p_service_id is null then
    insert into public.services (
      shop_id, name, description, duration_minutes, buffer_minutes, price_krw, deposit_krw, is_active, is_public
    ) values (
      owned_shop.id, p_name, p_description, p_duration, p_buffer, p_price, p_deposit, p_state <> 'inactive', p_state = 'public'
    ) returning id into saved_id;
    return saved_id;
  end if;

  update public.services
  set name = p_name, description = p_description, duration_minutes = p_duration,
      buffer_minutes = p_buffer, price_krw = p_price, deposit_krw = p_deposit,
      is_active = p_state <> 'inactive', is_public = p_state = 'public', revision = revision + 1
  where shop_id = owned_shop.id and id = p_service_id;
  return p_service_id;
end;
$$;

create function public.r4_save_hours(p_shop_id uuid, p_revision integer, p_periods jsonb)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  periods public.shop_weekly_periods[];
begin
  if p_revision is null or jsonb_typeof(p_periods) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'r4_hours_input';
  end if;
  perform r4_private.lock_shop(p_shop_id, p_revision);
  if jsonb_array_length(p_periods) > 96 then
    raise exception using errcode = '22023', message = 'r4_hours_input';
  end if;

  select array_agg(row(p_shop_id, p.iso_weekday, p.period_kind, p.start_minute, p.end_minute)::public.shop_weekly_periods)
  into periods
  from jsonb_to_recordset(p_periods) as p(iso_weekday smallint, period_kind text, start_minute smallint, end_minute smallint);

  if exists (
    select from unnest(periods) p
    where p.iso_weekday is null or p.iso_weekday not between 1 and 7
      or p.period_kind is null or p.period_kind not in ('opening', 'break')
      or p.start_minute is null or p.start_minute < 0 or p.start_minute % 15 <> 0
      or p.end_minute is null or p.end_minute > 1440 or p.end_minute % 15 <> 0
      or p.end_minute <= p.start_minute
  ) then
    raise exception using errcode = '22023', message = 'r4_hours_input';
  end if;

  if exists (
    select from (
      select p.start_minute, lag(p.end_minute) over (
        partition by p.iso_weekday, p.period_kind order by p.start_minute, p.end_minute
      ) as previous_end
      from unnest(periods) p
    ) ordered where ordered.start_minute < ordered.previous_end
  ) then
    raise exception using errcode = '22023', message = 'r4_hours_overlap';
  end if;

  if exists (
    select from unnest(periods) b
    where b.period_kind = 'break' and not exists (
      select from unnest(periods) o
      where o.period_kind = 'opening' and o.iso_weekday = b.iso_weekday
      having range_agg(int4range(o.start_minute, o.end_minute)) @> int4range(b.start_minute, b.end_minute)
    )
  ) then
    raise exception using errcode = '22023', message = 'r4_break_outside';
  end if;

  delete from public.shop_weekly_periods where shop_id = p_shop_id;
  insert into public.shop_weekly_periods (shop_id, iso_weekday, period_kind, start_minute, end_minute)
  select p.shop_id, p.iso_weekday, p.period_kind, p.start_minute, p.end_minute from unnest(periods) p;
  update public.shops set policy_revision = policy_revision + 1 where id = p_shop_id;
end;
$$;

create function public.r4_save_policy(
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

  if p_notice is null or p_notice < 0 or p_window is null or p_window < 1
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

revoke all on function
  public.r4_save_shop(uuid, integer, text, text),
  public.r4_save_service(uuid, uuid, integer, text, text, integer, integer, integer, integer, text),
  public.r4_save_hours(uuid, integer, jsonb),
  public.r4_save_policy(uuid, integer, integer, integer, integer, integer, text, text, text, text, text)
from public, anon, authenticated, service_role;

grant execute on function
  public.r4_save_shop(uuid, integer, text, text),
  public.r4_save_service(uuid, uuid, integer, text, text, integer, integer, integer, integer, text),
  public.r4_save_hours(uuid, integer, jsonb),
  public.r4_save_policy(uuid, integer, integer, integer, integer, integer, text, text, text, text, text)
to authenticated;

notify pgrst, 'reload schema';
