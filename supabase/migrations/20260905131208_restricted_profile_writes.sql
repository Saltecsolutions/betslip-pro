begin;
drop policy tipster_update_own on public.tipsters;
drop policy tipster_update_own_profile on public.tipsters;
create policy tipster_update_active on public.tipsters for update to authenticated using(user_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and status='active')) with check(user_id=auth.uid() and exists(select 1 from public.profiles where id=auth.uid() and status='active'));
commit;
