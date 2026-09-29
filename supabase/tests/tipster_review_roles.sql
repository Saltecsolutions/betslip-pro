begin;
select set_config('test.staff',gen_random_uuid()::text,true),set_config('test.seller',gen_random_uuid()::text,true);
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select current_setting(k)::uuid,'audit-'||current_setting(k)||'@example.invalid',now(),'{"requested_role":"tipster","age_confirmed":true}'::jsonb
from unnest(array['test.staff','test.seller']) k;
update public.profiles set role='super_admin' where id=current_setting('test.staff')::uuid;
select set_config('test.staff_tipster',(select id::text from public.tipsters where user_id=current_setting('test.staff')::uuid),true),set_config('test.seller_tipster',(select id::text from public.tipsters where user_id=current_setting('test.seller')::uuid),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('test.seller'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin
  perform public.admin_set_tipster_status(current_setting('test.seller_tipster')::uuid,'active');
  raise exception 'Self approval allowed';
 exception when raise_exception then if sqlerrm<>'forbidden' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('test.staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.admin_set_tipster_status(current_setting('test.staff_tipster')::uuid,'active');
select public.admin_set_tipster_status(current_setting('test.staff_tipster')::uuid,'suspended');
select public.admin_set_tipster_status(current_setting('test.staff_tipster')::uuid,'rejected');
select public.admin_set_tipster_status(current_setting('test.seller_tipster')::uuid,'active');
reset role;
do $$begin
 if (select role from public.profiles where id=current_setting('test.staff')::uuid)<>'super_admin' then raise exception 'Staff role overwritten';end if;
 if (select role from public.profiles where id=current_setting('test.seller')::uuid)<>'tipster' then raise exception 'Seller promotion failed';end if;
 if (select count(*) from public.audit_logs where actor_user_id=current_setting('test.staff')::uuid and action='tipster_status_changed')<>4 then raise exception 'Missing audit record';end if;
end $$;
rollback;
select 'PASS: staff roles preserved, seller approved, self approval denied; all fixtures rolled back' as result;
