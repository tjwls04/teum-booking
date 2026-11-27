-- Local Supabase only. Apply R2 and R4 first. All fixtures roll back.
begin;

insert into auth.users (id, email, email_confirmed_at) values
  ('f4000000-0000-4000-8000-000000000001', 'r4-owner-a@example.invalid', now()),
  ('f4000000-0000-4000-8000-000000000002', 'r4-owner-b@example.invalid', now()),
  ('f4000000-0000-4000-8000-000000000003', 'r4-pending@example.invalid', null);

do $$
declare
  endpoint text;
  role_name text;
  relation text;
begin
  foreach endpoint in array array[
    'public.r4_save_shop(uuid,integer,text,text)',
    'public.r4_save_service(uuid,uuid,integer,text,text,integer,integer,integer,integer,text)',
    'public.r4_save_hours(uuid,integer,jsonb)',
    'public.r4_save_policy(uuid,integer,integer,integer,integer,integer,text,text,text,text,text)'
  ] loop
    if not has_function_privilege('authenticated', endpoint, 'EXECUTE')
      or has_function_privilege('anon', endpoint, 'EXECUTE')
      or has_function_privilege('service_role', endpoint, 'EXECUTE')
    then
      raise exception 'Unexpected RPC privileges for %', endpoint;
    end if;
    if not exists (
      select from pg_catalog.pg_proc
      where oid = endpoint::regprocedure and prosecdef and 'search_path=""' = any(proconfig)
    ) then
      raise exception 'Unsafe RPC function settings for %', endpoint;
    end if;
  end loop;

  foreach role_name in array array['anon', 'authenticated', 'service_role'] loop
    foreach relation in array array['shops','shop_weekly_periods','services','shop_bank_accounts'] loop
      if has_table_privilege(role_name, 'public.' || relation, 'INSERT, UPDATE, DELETE, TRUNCATE')
        or has_any_column_privilege(role_name, 'public.' || relation, 'INSERT, UPDATE')
      then
        raise exception 'Direct table writes available to % on %', role_name, relation;
      end if;
    end loop;
  end loop;

  if has_schema_privilege('authenticated', 'r4_private', 'USAGE') then
    raise exception 'Owner RPC helpers are exposed';
  end if;
end;
$$;

-- Keep the original validation cases usable both before and after the idempotent entry point.
create function pg_temp.r4_verify_create(
  p_shop uuid,p_name text,p_description text,p_duration integer,p_buffer integer,p_price integer,p_deposit integer,p_state text
) returns uuid language plpgsql as $$
begin
  if to_regprocedure('public.r5_create_service(uuid,uuid,text,text,integer,integer,integer,integer,text)') is not null then
    return public.r5_create_service(p_shop,gen_random_uuid(),p_name,p_description,p_duration,p_buffer,p_price,p_deposit,p_state);
  end if;
  return public.r4_save_service(p_shop,null,null,p_name,p_description,p_duration,p_buffer,p_price,p_deposit,p_state);
end;
$$;

set local role anon;
do $$
begin
  begin
    perform public.r4_save_shop(null, null, 'Blocked', 'r4-blocked');
    raise exception 'Anonymous RPC was accepted';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
set local role authenticated;

do $$
declare
  a_claims constant text := '{"sub":"f4000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}';
  b_claims constant text := '{"sub":"f4000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}';
  pending_claims constant text := '{"sub":"f4000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}';
  anonymous_claims constant text := '{"sub":"f4000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}';
  a_shop uuid;
  b_shop uuid;
  a_service uuid;
  b_service uuid;
  test_case record;
  valid_hours constant jsonb := '[
    {"iso_weekday":1,"period_kind":"opening","start_minute":540,"end_minute":720},
    {"iso_weekday":1,"period_kind":"opening","start_minute":720,"end_minute":1080},
    {"iso_weekday":1,"period_kind":"break","start_minute":705,"end_minute":735},
    {"iso_weekday":7,"period_kind":"opening","start_minute":1380,"end_minute":1440}
  ]';
begin
  perform set_config('request.jwt.claims', pending_claims, true);
  begin
    perform public.r4_save_shop(null, null, 'Blocked', 'r4-blocked');
    raise exception 'Unconfirmed email can save a shop';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', a_claims, true);
  a_shop := public.r4_save_shop(null, null, 'Shop A', 'r4-shop-a');
  if public.r4_save_shop(null, null, 'Overwrite', 'r4-overwrite') is distinct from a_shop
    or not exists (select from public.shops where id = a_shop and name = 'Shop A' and policy_revision = 1)
  then
    raise exception 'First shop retry did not preserve original values';
  end if;
  perform public.r4_save_shop(a_shop, 1, 'Edited shop A', 'r4-edited-shop-a');

  perform set_config('request.jwt.claims', b_claims, true);
  begin
    perform public.r4_save_shop(null, null, 'Shop B', 'r4-edited-shop-a');
    raise exception 'Duplicate slug was accepted';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r4_slug_taken' then raise; end if;
  end;
  b_shop := public.r4_save_shop(null, null, 'Shop B', 'r4-shop-b');
  b_service := pg_temp.r4_verify_create(b_shop, 'Service B', '', 30, 0, 8000, 0, 'public');
  perform public.r4_save_hours(b_shop, 1, valid_hours);
  perform public.r4_save_policy(b_shop, 2, 120, 60, 0, 60, 'Cancel rules B', 'Deposit rules B',
    'Test bank B', '123456', 'Test B');

  perform set_config('request.jwt.claims', anonymous_claims, true);
  begin
    perform public.r4_save_shop(a_shop, 2, 'Blocked', 'r4-blocked');
    raise exception 'Anonymous Auth JWT can save shop settings';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', a_claims, true);
  if exists (select from public.shops where id = b_shop)
    or exists (select from public.services where shop_id = b_shop)
    or exists (select from public.shop_weekly_periods where shop_id = b_shop)
    or exists (select from public.shop_bank_accounts where shop_id = b_shop)
  then
    raise exception 'Owner A can read private shop B data';
  end if;

  for test_case in select * from (values
    (format('select public.r4_save_shop(%L,3,%L,%L)', b_shop, 'Blocked', 'r4-blocked'), '42501', 'r4_owner'),
    (format('select pg_temp.r4_verify_create(%L,%L,%L,30,0,9000,0,%L)', b_shop, 'Blocked', '', 'private'), '42501', 'r4_owner'),
    (format('select public.r4_save_service(%L,%L,1,%L,%L,30,0,9000,0,%L)', a_shop, b_service, 'Blocked', '', 'private'), '42501', 'r4_owner'),
    (format('select public.r4_save_hours(%L,3,%L)', b_shop, '[]'), '42501', 'r4_owner'),
    (format('select public.r4_save_policy(%L,3,120,60,0,60,%L,%L,%L,%L,%L)', b_shop, '', '', '', '', ''), '42501', 'r4_owner'),
    (format('select public.r4_save_shop(%L,1,%L,%L)', a_shop, 'Stale', 'r4-stale'), 'PT409', 'r4_stale'),
    (format('select public.r4_save_shop(%L,2,%L,%L)', a_shop, E'\t\n', 'r4-blank'), '22023', 'r4_shop_input'),
    (format('select pg_temp.r4_verify_create(%L,%L,%L,20,0,10000,0,%L)', a_shop, 'Off-grid', '', 'private'), '22023', 'r4_service_input'),
    (format('select pg_temp.r4_verify_create(%L,%L,%L,30,0,10000,15000,%L)', a_shop, 'Too large', '', 'private'), '22023', 'r4_service_input'),
    (format('select pg_temp.r4_verify_create(%L,%L,%L,30,15,20000,5000,%L)', a_shop, 'Needs account', '', 'public'), '22023', 'r4_deposit_requirements'),
    (format('select public.r4_save_hours(%L,2,%L)', a_shop,
      '[{"iso_weekday":1,"period_kind":"opening","start_minute":541,"end_minute":600}]'), '22023', 'r4_hours_input'),
    (format('select public.r4_save_hours(%L,2,%L)', a_shop,
      '[{"iso_weekday":1,"period_kind":"opening","start_minute":540,"end_minute":720},
        {"iso_weekday":1,"period_kind":"opening","start_minute":660,"end_minute":1080}]'), '22023', 'r4_hours_overlap'),
    (format('select public.r4_save_hours(%L,2,%L)', a_shop,
      '[{"iso_weekday":1,"period_kind":"opening","start_minute":540,"end_minute":1080},
        {"iso_weekday":1,"period_kind":"break","start_minute":705,"end_minute":750},
        {"iso_weekday":1,"period_kind":"break","start_minute":735,"end_minute":780}]'), '22023', 'r4_hours_overlap'),
    (format('select public.r4_save_hours(%L,2,%L)', a_shop,
      '[{"iso_weekday":1,"period_kind":"opening","start_minute":540,"end_minute":720},
        {"iso_weekday":1,"period_kind":"break","start_minute":705,"end_minute":735}]'), '22023', 'r4_break_outside'),
    (format('select public.r4_save_policy(%L,2,120,60,0,45,%L,%L,%L,%L,%L)', a_shop, '', '', '', '', ''), '22023', 'r4_policy_input'),
    (format('select public.r4_save_policy(%L,2,120,60,0,60,%L,%L,%L,%L,%L)', a_shop, '', '', 'Test bank', '', ''), '22023', 'r4_bank_input')
  ) as cases(statement, expected_code, expected_message)
  loop
    begin
      execute test_case.statement;
      raise exception 'Invalid configuration was accepted';
    exception when others then
      if sqlstate <> test_case.expected_code or sqlerrm <> test_case.expected_message then
        raise;
      end if;
    end;
  end loop;

  if exists (select from public.shop_weekly_periods where shop_id = a_shop)
    or exists (select from public.shop_bank_accounts where shop_id = a_shop)
    or not exists (select from public.shops where id = a_shop and name = 'Edited shop A' and policy_revision = 2)
  then
    raise exception 'Rejected writes changed saved settings';
  end if;

  perform public.r4_save_hours(a_shop, 2, valid_hours);
  if (select count(*) from public.shop_weekly_periods where shop_id = a_shop) <> 4
    or exists (select from public.shop_weekly_periods where shop_id = a_shop and iso_weekday = 2)
  then
    raise exception 'Expected adjacent intervals, local midnight and closed weekdays';
  end if;

  perform public.r4_save_policy(a_shop, 3, 90, 45, 30, 120, 'Cancel rules', 'Deposit rules',
    'Test bank A', '1234-5678', 'Test A');
  a_service := pg_temp.r4_verify_create(a_shop, 'Service A', 'Details', 30, 15, 20000, 5000, 'public');

  begin
    perform public.r4_save_policy(a_shop, 4, 90, 45, 30, 120, 'Cancel rules', 'Deposit rules', '', '', '');
    raise exception 'A public deposit service lost its bank account';
  exception when invalid_parameter_value then
    if sqlerrm <> 'r4_deposit_requirements' then raise; end if;
  end;
  begin
    perform public.r4_save_policy(a_shop, 4, 90, 45, 30, 120, E'\t\n', 'Deposit rules',
      'Test bank A', '1234-5678', 'Test A');
    raise exception 'A public deposit service lost its cancellation policy';
  exception when invalid_parameter_value then
    if sqlerrm <> 'r4_deposit_requirements' then raise; end if;
  end;

  perform public.r4_save_service(a_shop, a_service, 1, 'Inactive service A', '', 45, 15, 20000, 5000, 'inactive');
  if not exists (select from public.services where id = a_service and not is_public and not is_active and revision = 2) then
    raise exception 'Deactivation did not increment service revision';
  end if;
  begin
    perform public.r4_save_service(a_shop, a_service, 1, 'Stale service', '', 30, 0, 10000, 0, 'public');
    raise exception 'Stale service update was accepted';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'r4_stale' then raise; end if;
  end;

  perform public.r4_save_policy(a_shop, 4, 90, 45, 30, 120, '', '', '', '', '');
  perform public.r4_save_hours(a_shop, 5, '[]');
  if exists (select from public.shop_bank_accounts where shop_id = a_shop)
    or exists (select from public.shop_weekly_periods where shop_id = a_shop)
    or not exists (select from public.shops where id = a_shop and policy_revision = 6 and booking_window_days = 45)
  then
    raise exception 'Account removal or closing the week did not persist';
  end if;

  perform set_config('request.jwt.claims', b_claims, true);
  if exists (select from public.services where id = a_service)
    or not exists (select from public.services where id = b_service and is_public)
    or not exists (select from public.shop_bank_accounts where shop_id = b_shop)
  then
    raise exception 'Owner B isolation failed';
  end if;
end;
$$;

reset role;
rollback;
select 'R4 shop settings checks passed' as result;
