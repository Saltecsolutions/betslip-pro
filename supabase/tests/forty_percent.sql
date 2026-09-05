begin;
-- Isolated order table exercises the production trigger without changing real orders.
create temp table allocation_orders (like public.purchases including defaults);
insert into allocation_orders(id,user_id,tipster_id,prediction_id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,wht_bps,wht_allocation_tzs,platform_net_tzs)
values(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1000,300,700,500,50,250);
create trigger allocation_test before insert or update on allocation_orders for each row execute function engine.allocate_sale();
insert into allocation_orders(id,user_id,tipster_id,prediction_id,amount_tzs)
select gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),n from unnest(array[1000,1001,1500,2000,3000,5000,7500]) n;
update allocation_orders set payment_status='submitted';
do $$begin
 if (select count(*) from allocation_orders where tipster_commission_tzs=700 and platform_commission_tzs=300 and platform_net_tzs=250)<>1 then raise exception 'FAIL legacy order changed';end if;
 if (select count(*) from allocation_orders where tipster_commission_tzs=400 and platform_commission_tzs=600 and wht_allocation_tzs=50 and platform_net_tzs=550)<>1 then raise exception 'FAIL new 40/60 order';end if;
 if exists(select 1 from allocation_orders where tipster_commission_tzs+platform_commission_tzs<>amount_tzs or platform_net_tzs+wht_allocation_tzs<>platform_commission_tzs) then raise exception 'FAIL rounding loses money';end if;
 begin update allocation_orders set amount_tzs=2000 where tipster_commission_tzs=700;raise exception 'FAIL legacy order repriced';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 if exists(select 1 from pg_proc where oid in ('public.accept_policies(text,text,boolean)'::regprocedure,'public.policy_status()'::regprocedure) and prosecdef) then raise exception 'FAIL policy wrapper privilege regression';end if;
end $$;
rollback;
