begin;
create temp table access_ids(k text primary key,id uuid);
insert into access_ids values('partner',gen_random_uuid()),('other',gen_random_uuid());
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,case when k='partner' then 'jdaking08@gmail.com' else id||'@test.invalid' end,now(),'{}' from access_ids;
insert into public.policy_acceptances(user_id,document,version,locale) select id,d,case when d='seller' then '2026-09-05-v2' else '2026-09-05' end,'en' from access_ids cross join unnest(array['terms','privacy','adult']) d;
grant select on access_ids to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from access_ids where k='partner'),true);
set local role authenticated;
do $$begin
 if not public.revenue_access() then raise exception 'FAIL partner access';end if;
 perform public.platform_revenue_summary();
 if public.is_admin() then raise exception 'FAIL partner elevated';end if;
 begin perform public.payout_queue();raise exception 'FAIL partner payout data';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.configure_wht_allocation(0,'Unauthorized allocation change');raise exception 'FAIL partner financial mutation';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin select * from engine.prices;raise exception 'FAIL price table exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;
update auth.users set email_confirmed_at=null where id=(select id from access_ids where k='partner');
set local role authenticated;
do $$begin if public.revenue_access() then raise exception 'FAIL unconfirmed partner';end if;end $$;
select set_config('request.jwt.claim.sub',(select id::text from access_ids where k='other'),true);
do $$begin if public.revenue_access() then raise exception 'FAIL unrelated reader';end if;end $$;
reset role;
do $$declare r record;begin
 if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='engine' and c.relkind='r' and not c.relrowsecurity) then raise exception 'FAIL missing RLS';end if;
 if has_function_privilege('authenticated','engine.review_price(uuid)','execute') or has_function_privilege('authenticated','engine.daily_reviews()','execute') then raise exception 'FAIL internal engine exposed';end if;
 for r in select column_name from information_schema.columns where table_schema='public' and table_name='predictions' loop
 if has_column_privilege('authenticated','public.predictions',r.column_name,'INSERT') or has_column_privilege('authenticated','public.predictions',r.column_name,'UPDATE') then raise exception 'FAIL client prediction writes';end if;
 end loop;
 if has_function_privilege('anon','public.platform_revenue_summary()','execute') then raise exception 'FAIL anonymous revenue';end if;
end $$;
rollback;
