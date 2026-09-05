begin;
alter table public.predictions add column confidence smallint check(confidence between 1 and 100);
alter table public.predictions add column analysis text check(length(analysis) between 20 and 1500);
grant select(confidence,analysis) on public.predictions to anon,authenticated;
create table public.purchase_ratings(purchase_id uuid primary key references public.purchases(id),user_id uuid not null references public.profiles(id),rating smallint not null check(rating between 1 and 5),created_at timestamptz not null default now());
alter table public.purchase_ratings enable row level security;
revoke all on public.purchase_ratings from anon,authenticated;
grant select,insert(purchase_id,user_id,rating) on public.purchase_ratings to authenticated;
create policy ratings_read on public.purchase_ratings for select to authenticated using(user_id=(select auth.uid()) or public.is_admin());
create policy ratings_insert on public.purchase_ratings for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.purchases p where p.id=purchase_id and p.user_id=auth.uid() and p.payment_status='paid'));
create index ratings_user on public.purchase_ratings(user_id);
create table public.tipster_reviews(tipster_id uuid primary key references public.tipsters(id),on_hold boolean not null default false,reason text not null,reviewed_by uuid not null references public.profiles(id),reviewed_at timestamptz not null default now());
alter table public.tipster_reviews enable row level security;
revoke all on public.tipster_reviews from anon,authenticated;
grant select on public.tipster_reviews to authenticated;
create policy reviews_admin on public.tipster_reviews for select to authenticated using(public.is_admin());
create or replace function public.guard_prediction_record() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='DELETE' then
   if old.published_at is not null or old.match_date<=now() then raise exception 'Published history cannot be deleted'; end if; return old;
 end if;
 if TG_OP='INSERT' then
   if new.match_date<=now() or new.published_at is not null or new.status not in ('draft','pending') or new.result<>'pending' or new.settled_at is not null then raise exception 'New predictions must be future unpublished submissions'; end if;
   return new;
 end if;
 if old.published_at is not null or old.match_date<=now() then
   if (to_jsonb(new)-'status'-'result'-'settled_at') is distinct from (to_jsonb(old)-'status'-'result'-'settled_at') then raise exception 'Published history is immutable'; end if;
   if new.status is distinct from old.status and not(old.status='published' and new.status='resulted') then raise exception 'Published history cannot be hidden'; end if;
 end if;
 if new.status='published' and old.status<>'published' then
   if new.odds is null or new.odds<=1 or new.match_date<=now() then raise exception 'Future kickoff and valid odds required'; end if;
   new.published_at:=clock_timestamp();
 end if;
 if new.result is distinct from old.result or new.status='resulted' then
   if not exists(select 1 from public.settlement_events where prediction_id=new.id and result=new.result) then raise exception 'Verified settlement evidence required'; end if;
   if old.result<>'pending' and (new.result is distinct from old.result or new.settled_at is distinct from old.settled_at) then raise exception 'Settlement is immutable'; end if;
 elsif new.settled_at is distinct from old.settled_at then raise exception 'Settlement timestamp requires a result';
 end if;
 return new;
end $$;
create function public.guard_evidence() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Audit evidence is append-only'; end $$;
create trigger settlement_append_only before update or delete on public.settlement_events for each row execute function public.guard_evidence();
create trigger audit_append_only before update or delete on public.audit_logs for each row execute function public.guard_evidence();
create function public.guard_selection_mapping() returns trigger language plpgsql security definer set search_path='' as $$
declare pid uuid;
begin
 pid:=case when TG_OP='DELETE' then old.prediction_id else new.prediction_id end;
 if exists(select 1 from public.predictions where id=pid and published_at is not null) or (TG_OP='UPDATE' and exists(select 1 from public.predictions where id=old.prediction_id and published_at is not null)) then
   if TG_OP<>'UPDATE' then raise exception 'Published selections are immutable'; end if;
   if (to_jsonb(new)-'result'-'source_reference') is distinct from (to_jsonb(old)-'result'-'source_reference') then raise exception 'Published selections are immutable'; end if;
   if old.result<>'pending' and new is distinct from old then raise exception 'Selection result is immutable'; end if;
 end if;
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
create trigger selection_mapping_lock before insert or update or delete on public.prediction_selections for each row execute function public.guard_selection_mapping();
create function public.audit_publication() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.published_at is not null and old.published_at is null then
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'prediction_published','prediction',new.id::text,jsonb_build_object('published_at',new.published_at,'kickoff',new.match_date,'odds',new.odds,'selection_count',new.selection_count));
 end if; return new;
end $$;
create trigger publication_audit after update on public.predictions for each row execute function public.audit_publication();
-- One-unit returns use effective settled odds, with voids excluded from decided picks.
create function public.performance_window(p_tipster_id uuid,p_days integer default null) returns jsonb language sql stable security definer set search_path='' as $$
 with records as (
 select p.*,coalesce(s.settled_odds,p.odds) effective_odds from public.predictions p left join public.settlement_events s on s.prediction_id=p.id
 where p.tipster_id=p_tipster_id and p.status in ('published','resulted') and (p_days is null or p.settled_at>=now()-make_interval(days=>p_days))
 ), totals as (
 select count(*) filter(where result in ('won','lost')) decided,count(*) filter(where result<>'pending') settled,count(*) filter(where result='won') wins,count(*) filter(where result='lost') losses,count(*) filter(where result='void') voids,
 coalesce(sum(case when result='won' then effective_odds-1 when result='lost' then -1 else 0 end),0) profit,
 avg(odds) filter(where result in ('won','lost')) average_odds from records
 ) select jsonb_build_object('decided',decided,'settled',settled,'wins',wins,'losses',losses,'voids',voids,'profit',round(profit,2),'roi',round(100*profit/nullif(decided,0),2),'win_rate',round(100.0*wins/nullif(decided,0),1),'average_odds',round(average_odds,2),'form',coalesce((select jsonb_agg(result order by settled_at desc,id) from (select result,settled_at,id from records where result<>'pending' order by settled_at desc,id limit 5) f),'[]'::jsonb)) from totals;
$$;
create function public.expert_insights() returns jsonb language sql stable security definer set search_path='' as $$
 with data as (
 select t.id,t.sports_specialty,public.performance_window(t.id,null) all_time,public.performance_window(t.id,7) d7,public.performance_window(t.id,30) d30,public.performance_window(t.id,90) d90,
 (select round(avg(r.rating),2) from public.purchase_ratings r join public.purchases pu on pu.id=r.purchase_id where pu.tipster_id=t.id and pu.payment_status='paid') rating,
 (select count(*) from public.purchase_ratings r join public.purchases pu on pu.id=r.purchase_id where pu.tipster_id=t.id and pu.payment_status='paid') rating_count,
 not coalesce((select on_hold from public.tipster_reviews where tipster_id=t.id),false) compliant
 from public.tipsters t where t.verification_status='active'
 ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'sports_specialty',sports_specialty,'periods',jsonb_build_object('all',all_time,'7',d7,'30',d30,'90',d90),'rating',rating,'rating_count',rating_count,'compliant',compliant,'level',case
 when not compliant then 'New'
 when (all_time->>'decided')::int>=200 and (d90->>'decided')::int>=50 and (all_time->>'roi')::numeric>=5 and (d90->>'roi')::numeric>0 and (d30->>'roi')::numeric>0 and rating>=4.5 and rating_count>=20 then 'Elite'
 when (all_time->>'decided')::int>=75 and (d90->>'decided')::int>=20 and (all_time->>'roi')::numeric>0 and (d90->>'roi')::numeric>0 and rating>=4 and rating_count>=5 then 'Pro'
 when (all_time->>'decided')::int>=20 then 'Verified' else 'New' end)),'[]'::jsonb) from data;
$$;
create function public.prediction_card_signals() returns table(id uuid,buyers bigint,form jsonb) language sql stable security definer set search_path='' as $$
 select p.id,(select count(*) from public.purchases pu where pu.prediction_id=p.id and pu.payment_status='paid'),public.performance_window(p.tipster_id,30)->'form'
 from public.predictions p where p.status='published' and p.match_date>now();
$$;
create or replace function public.tipster_business_summary() returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid; answer jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select id into tid from public.tipsters where user_id=auth.uid(); if tid is null then raise exception 'Tipster account required'; end if;
 select jsonb_build_object('sales',count(*) filter(where payment_status='paid'),'gross',coalesce(sum(amount_tzs) filter(where payment_status='paid'),0),'platform',coalesce(sum(platform_commission_tzs) filter(where payment_status='paid'),0),'earnings',coalesce(sum(tipster_commission_tzs) filter(where payment_status='paid'),0),'fees',coalesce(sum(processing_fee_tzs) filter(where payment_status='paid'),0),'predictions_sold',count(distinct prediction_id) filter(where payment_status='paid'),'conversion',round(100.0*count(*) filter(where payment_status='paid')/nullif(count(*) filter(where payment_status<>'refunded'),0),1),'followers',(select count(*) from public.tipster_follows where tipster_id=tid),'rating',(select round(avg(r.rating),2) from public.purchase_ratings r join public.purchases pu on pu.id=r.purchase_id where pu.tipster_id=tid and pu.payment_status='paid')) into answer from public.purchases where tipster_id=tid;
 return answer;
end $$;
create function public.admin_review_tipster(p_id uuid,p_hold boolean,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if p_hold is null or length(btrim(coalesce(p_reason,'')))<10 then raise exception 'Review decision and reason required'; end if;
 insert into public.tipster_reviews values(p_id,p_hold,btrim(p_reason),auth.uid(),now()) on conflict(tipster_id) do update set on_hold=excluded.on_hold,reason=excluded.reason,reviewed_by=excluded.reviewed_by,reviewed_at=excluded.reviewed_at;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'tipster_integrity_review','tipster',p_id::text,jsonb_build_object('on_hold',p_hold,'reason',p_reason));
end $$;
create function public.admin_integrity_signals() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.display_name,'on_hold',coalesce(r.on_hold,false),'reason',r.reason,'signals',array_remove(array[
 case when e.settled>=20 and e.win_rate>=90 then 'high_win_rate' end,
 case when e.settled_30d>=20 and e.roi_30d>=100 then 'extreme_roi' end,
 case when exists(select 1 from public.predictions p where p.tipster_id=t.id and p.published_at>=p.match_date-interval '5 minutes') then 'late_publication' end,
 case when exists(select 1 from public.disputes d join public.purchases pu on pu.id=d.purchase_id where pu.tipster_id=t.id and d.status in ('open','approved')) then 'buyer_dispute' end,
 case when exists(select 1 from public.predictions p where p.tipster_id=t.id and p.status='published' and p.result='pending' and p.match_date<now()-interval '48 hours') then 'overdue_settlement' end
 ],null))),'[]'::jsonb) from public.tipsters t left join public.tipster_performance() e on e.id=t.id left join public.tipster_reviews r on r.tipster_id=t.id where t.verification_status='active');
end $$;
revoke all on function public.guard_evidence(),public.guard_selection_mapping(),public.audit_publication(),public.performance_window(uuid,integer),public.expert_insights(),public.prediction_card_signals(),public.admin_review_tipster(uuid,boolean,text),public.admin_integrity_signals() from public,anon,authenticated;
grant execute on function public.expert_insights(),public.prediction_card_signals() to anon,authenticated;
grant execute on function public.admin_review_tipster(uuid,boolean,text),public.admin_integrity_signals() to authenticated;
grant all on public.purchase_ratings,public.tipster_reviews to service_role;
commit;
