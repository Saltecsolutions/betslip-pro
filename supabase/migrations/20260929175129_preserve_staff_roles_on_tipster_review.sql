-- Reviewing a seller account must not grant, remove, or reactivate staff access.
create or replace function public.admin_set_tipster_status(p_tipster_id uuid, p_status public.account_status)
returns void language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 if not public.is_admin() then raise exception 'forbidden'; end if;
 if p_status is null or p_status not in ('active','rejected','suspended') then
  raise exception 'Invalid review status';
 end if;
 update public.tipsters set verification_status=p_status where id=p_tipster_id returning user_id into uid;
 if uid is null then raise exception 'Tipster not found'; end if;
 update public.profiles
 set role=case when p_status='active' then 'tipster'::public.app_role else 'bettor'::public.app_role end,
     status=case when p_status='active' then 'active'::public.account_status else status end
 where id=uid and role in ('bettor','tipster');
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'tipster_status_changed','tipster',p_tipster_id::text,jsonb_build_object('status',p_status));
end $$;
revoke all on function public.admin_set_tipster_status(uuid,public.account_status) from public,anon;
grant execute on function public.admin_set_tipster_status(uuid,public.account_status) to authenticated;
