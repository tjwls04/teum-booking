-- Apply this file in a single transaction. Configure Cron separately.
create schema r7_private;
revoke all on schema r7_private from public, anon, authenticated, service_role;

create function r7_private.expire_shop(p_shop uuid, p_now timestamptz, p_limit integer)
returns integer language sql set search_path = '' as $$
  with due as (
    select id from public.bookings
    where shop_id = p_shop and status = 'pending_deposit' and deposit_status = 'awaiting_transfer'
      and deposit_due_at <= p_now
    order by deposit_due_at,id limit p_limit
  ), expired as (
    update public.bookings b set status = 'expired',
      money_followup_status = case when exists (
        select from public.booking_events e where e.shop_id = p_shop and e.booking_id = b.id
          and e.event_type = 'deposit_discrepancy'
      ) then 'review_needed' else b.money_followup_status end
    from due where b.shop_id = p_shop and b.id = due.id returning b.id
  ), released as (
    delete from public.occupied_slots o using expired e
    where o.shop_id = p_shop and o.booking_id = e.id
  ), audit as (
    insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind)
    select p_shop, id, 'expired', gen_random_uuid(), 'system' from expired returning id
  )
  select count(*)::integer from audit
$$;

-- Existing callers already take the shop row lock.
create or replace function r5_private.expire(p_shop_id uuid, p_now timestamptz)
returns void language plpgsql set search_path = '' as $$
begin
  perform r7_private.expire_shop(p_shop_id, p_now, null);
end;
$$;

-- Only the database owner runs this invoker function. Each tick bounds its work.
create function r7_private.expire_due()
returns integer language plpgsql set search_path = '' as $$
declare
  target uuid;
  total integer := 0;
begin
  for target in
    select s.id from public.shops s
    where exists (
      select from public.bookings b where b.shop_id = s.id and b.status = 'pending_deposit'
        and b.deposit_status = 'awaiting_transfer' and b.deposit_due_at <= statement_timestamp()
    )
    order by s.id limit 25 for update of s skip locked
  loop
    total := total + r7_private.expire_shop(target, clock_timestamp(), 100);
  end loop;
  return total;
end;
$$;

create function public.r7_record(
  p_shop uuid, p_booking uuid, p_revision integer, p_operation text,
  p_amount integer, p_reason text, p_checked boolean, p_key uuid
) returns text language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
  baseline timestamptz := clock_timestamp();
  booking public.bookings;
  previous public.booking_events;
  payload jsonb;
  event_name text;
  received bigint;
  refunded bigint;
begin
  p_reason := nullif(r4_private.clean_text(p_reason), '');
  if p_booking is null or p_key is null or p_revision is null or p_revision < 1
    or p_operation is null or p_operation not in ('confirm','receipt','refund','no_refund')
    or p_checked is distinct from true or p_amount is null
    or (p_operation = 'no_refund' and p_amount <> 0)
    or (p_operation <> 'no_refund' and p_amount <= 0)
    or char_length(p_reason) > 200 or p_reason ~ '[[:cntrl:]]'
    or (p_operation <> 'confirm' and p_reason is null) then
    return 'r7_input';
  end if;

  payload := jsonb_build_array('r7', p_revision, p_operation, p_amount, p_reason);
  -- Use a normal result for later business-rule denials so due expiry still commits.
  perform r5_private.expire(shop.id, baseline);
  select * into booking from public.bookings b where b.shop_id = shop.id and b.id = p_booking for update;
  if not found then return 'r7_missing'; end if;

  select * into previous from public.booking_events e
  where e.shop_id = shop.id and e.booking_id = booking.id and e.event_key = p_key;
  if found then
    if previous.actor_kind = 'owner' and previous.details->'request' = payload then
      return previous.event_type;
    end if;
    return 'r7_key';
  end if;
  if booking.revision <> p_revision then return 'r7_stale'; end if;
  if booking.deposit_krw <= 0 then return 'r7_state'; end if;

  if p_operation = 'confirm' then
    if booking.status <> 'pending_deposit' or booking.deposit_status not in ('awaiting_transfer','reported') then
      return 'r7_state';
    end if;
    if p_amount = booking.deposit_krw then
      update public.bookings set status = 'confirmed', deposit_status = 'verified',
        deposit_verified_at = baseline, deposit_verified_by = shop.owner_user_id
      where shop_id = shop.id and id = booking.id;
      event_name := 'deposit_verified';
    else
      if p_reason is null then return 'r7_reason'; end if;
      select * into previous from public.booking_events e
      where e.shop_id = shop.id and e.booking_id = booking.id and e.event_type = 'deposit_discrepancy'
      order by e.created_at desc,e.id desc limit 1;
      if found and previous.details->'amount_krw' = to_jsonb(p_amount) and previous.details->>'reason' = p_reason then
        return 'r7_duplicate';
      end if;
      -- The existing revision trigger tracks new money evidence without changing the reservation state.
      update public.bookings set revision = revision where shop_id = shop.id and id = booking.id;
      event_name := 'deposit_discrepancy';
    end if;
  elsif p_operation = 'receipt' then
    if booking.status not in ('expired','cancelled') or booking.deposit_status not in ('awaiting_transfer','reported') then
      return 'r7_state';
    end if;
    update public.bookings set deposit_status = 'verified', deposit_verified_at = baseline,
      deposit_verified_by = shop.owner_user_id, money_followup_status = 'review_needed'
    where shop_id = shop.id and id = booking.id;
    event_name := 'deposit_verified_after_close';
  else
    if booking.status not in ('expired','cancelled') or booking.money_followup_status <> 'review_needed' then
      return 'r7_state';
    end if;
    if p_operation = 'refund' then
      select coalesce(sum((e.details->>'amount_krw')::integer)
          filter (where e.event_type in ('deposit_verified','deposit_verified_after_close')),0),
        coalesce(sum((e.details->>'amount_krw')::integer)
          filter (where e.event_type = 'manual_refund_recorded'),0)
      into received,refunded
      from public.booking_events e
      where e.shop_id = shop.id and e.booking_id = booking.id
        and e.event_type in ('deposit_verified','deposit_verified_after_close','manual_refund_recorded');
      if p_amount > received - refunded then return 'r7_amount'; end if;
    end if;
    update public.bookings set money_followup_status = 'resolved_recorded'
    where shop_id = shop.id and id = booking.id;
    event_name := case when p_operation = 'refund' then 'manual_refund_recorded' else 'no_refund_recorded' end;
  end if;
  insert into public.booking_events (shop_id, booking_id, event_type, event_key, actor_kind, actor_user_id, details)
  values (shop.id, booking.id, event_name, p_key, 'owner', shop.owner_user_id,
    jsonb_build_object('request',payload,'amount_krw',p_amount,'reason',p_reason,'manual',true));
  return event_name;
end;
$$;

create function public.r7_deposits(p_shop uuid, p_tab text, p_page integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
begin
  if (p_tab is not null and p_tab not in ('waiting','reported','verified','review','resolved'))
    or p_page is null or p_page not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'r7_input';
  end if;
  perform r5_private.expire(shop.id, clock_timestamp());
  return (
    with classified as (
      select b.id, b.customer_name, b.service_name, b.starts_at, b.deposit_due_at,
        b.deposit_krw, b.status, b.deposit_status, b.created_at,
        case
          when b.money_followup_status = 'review_needed' or (
            b.status = 'pending_deposit' and exists (
              select from public.booking_events e where e.shop_id = shop.id and e.booking_id = b.id
                and e.event_type = 'deposit_discrepancy'
            )
          ) then 'review'
          when b.money_followup_status = 'resolved_recorded' then 'resolved'
          when b.deposit_status = 'verified' then 'verified'
          when b.status = 'pending_deposit' and b.deposit_status = 'reported' then 'reported'
          when b.status = 'pending_deposit' then 'waiting'
        end as category
      from public.bookings b where b.shop_id = shop.id and b.deposit_krw > 0
    ), summary as (
      select category,count(*) count from classified where category is not null group by category
    ), chosen as (
      select * from classified where category = p_tab
      order by created_at desc, id desc offset (p_page - 1) * 40 limit 41
    )
    select jsonb_build_object(
      'counts', coalesce((select jsonb_object_agg(category,count) from summary),'{}'::jsonb),
      'items', coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc,i.id desc) from chosen i),'[]'::jsonb)
    )
  );
end;
$$;

create function public.r7_deposit_detail(p_shop uuid, p_booking uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  shop public.shops := r4_private.lock_shop(p_shop, null);
begin
  perform r5_private.expire(shop.id, clock_timestamp());
  return (
    select jsonb_build_object(
      'id',b.id,'revision',b.revision,'customer_name',b.customer_name,'service_name',b.service_name,'starts_at',b.starts_at,
      'deposit_due_at',b.deposit_due_at,'deposit_krw',b.deposit_krw,'status',b.status,'deposit_status',b.deposit_status,
      'money_followup_status',b.money_followup_status,
      'refundable_krw', greatest(0,coalesce((
        select sum(case when e.event_type = 'manual_refund_recorded' then -(e.details->>'amount_krw')::bigint
          else (e.details->>'amount_krw')::bigint end)
        from public.booking_events e where e.shop_id = shop.id and e.booking_id = b.id
          and e.event_type in ('deposit_verified','deposit_verified_after_close','manual_refund_recorded')
      ),0)),
      'events',coalesce((
        select jsonb_agg(jsonb_build_object('id',e.id,'type',e.event_type,'at',e.created_at,
          'amount_krw',e.details->'amount_krw','reason',e.details->>'reason') order by e.created_at desc,e.id desc)
        from (select id,event_type,created_at,details from public.booking_events
          where shop_id = shop.id and booking_id = b.id and event_type in (
            'deposit_verified','deposit_verified_after_close','deposit_discrepancy','manual_refund_recorded',
            'no_refund_recorded','deposit_reported','deposit_reported_late','expired','cancelled'
          ) order by created_at desc,id desc limit 100) e
      ),'[]'::jsonb)
    )
    from public.bookings b where b.shop_id = shop.id and b.id = p_booking and b.deposit_krw > 0
  );
end;
$$;

revoke all on all functions in schema r7_private from public, anon, authenticated, service_role;
revoke all on function public.r7_record(uuid,uuid,integer,text,integer,text,boolean,uuid),
  public.r7_deposits(uuid,text,integer), public.r7_deposit_detail(uuid,uuid)
from public, anon, authenticated, service_role;
grant execute on function public.r7_record(uuid,uuid,integer,text,integer,text,boolean,uuid),
  public.r7_deposits(uuid,text,integer), public.r7_deposit_detail(uuid,uuid)
to authenticated;

-- Preserve the R5 endpoint and grant while supporting late follow-up after R6 cancellation.
create or replace function public.r5_confirmation(p_token_hash text, p_report boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  booking public.bookings;
  shop public.shops;
  baseline timestamptz;
  report_event text;
  can_report_late boolean;
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

  -- Record one late report even if cancellation already opened the case.
  can_report_late := booking.status in ('expired','cancelled') and booking.deposit_status = 'awaiting_transfer'
    and not exists (
      select from public.booking_events e where e.shop_id = shop.id and e.booking_id = booking.id
        and e.event_type = 'deposit_reported_late'
    );
  if p_report and booking.deposit_status = 'awaiting_transfer' then
    if booking.status = 'pending_deposit' then
      update public.bookings set deposit_status = 'reported'
      where shop_id = shop.id and id = booking.id returning * into booking;
      report_event := 'deposit_reported';
    elsif can_report_late then
      update public.bookings set money_followup_status = 'review_needed'
      where shop_id = shop.id and id = booking.id returning * into booking;
      report_event := 'deposit_reported_late';
      can_report_late := false;
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
    'canReport', can_report_late or (booking.status = 'pending_deposit' and booking.deposit_status = 'awaiting_transfer'),
    'phoneLast4', right(booking.customer_phone, 4),
    'account', case when booking.status = 'pending_deposit' and booking.deposit_status = 'awaiting_transfer'
      then jsonb_build_object('bank', booking.deposit_bank_name, 'number', booking.deposit_account_number, 'holder', booking.deposit_account_holder)
      else null end
  );
end;
$$;

revoke all on function public.r5_confirmation(text,boolean) from public, anon, authenticated, service_role;
grant execute on function public.r5_confirmation(text,boolean) to service_role;
notify pgrst, 'reload schema';
