-- V1: immutable records, secure previews, follow, activity, protection and settlement.
begin;
alter table public.predictions add column selection_count integer not null default 1 check(selection_count between 1 and 50);
alter table public.predictions add column settled_at timestamptz;
grant select(selection_count,settled_at) on public.predictions to anon,authenticated;
revoke select(match_name) on public.predictions from anon,authenticated;

create table public.tipster_follows(user_id uuid not null references public.profiles(id) on delete cascade,tipster_id uuid not null references public.tipsters(id),created_at timestamptz not null default now(),primary key(user_id,tipster_id));
alter table public.tipster_follows enable row level security;
revoke all on public.tipster_follows from anon,authenticated;
grant select,insert,delete on public.tipster_follows to authenticated;
create policy follow_read on public.tipster_follows for select to authenticated using(user_id=(select auth.uid()));
create policy follow_insert on public.tipster_follows for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.profiles where id=auth.uid() and status='active') and exists(select 1 from public.tipsters where id=tipster_id and verification_status='active'));
create policy follow_delete on public.tipster_follows for delete to authenticated using(user_id=(select auth.uid()));
create index follows_tipster on public.tipster_follows(tipster_id);

create table public.notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,kind text not null,title_en text not null,title_sw text not null,href text not null,read_at timestamptz,created_at timestamptz not null default now());
alter table public.notifications enable row level security;
revoke all on public.notifications from anon,authenticated;
grant select,update(read_at) on public.notifications to authenticated;
create policy notifications_read on public.notifications for select to authenticated using(user_id=(select auth.uid()));
create policy notifications_update on public.notifications for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create index notifications_user on public.notifications(user_id,created_at desc);

create table public.settlement_events(id uuid primary key default gen_random_uuid(),prediction_id uuid not null references public.predictions(id),result public.prediction_result not null check(result<>'pending'),source text not null,evidence text not null,actor_user_id uuid references public.profiles(id),created_at timestamptz not null default now(),unique(prediction_id));
alter table public.settlement_events enable row level security;
revoke all on public.settlement_events from anon,authenticated;
grant select on public.settlement_events to anon,authenticated;
create policy settlements_public on public.settlement_events for select using(exists(select 1 from public.predictions p where p.id=prediction_id and p.status in ('published','resulted')) or public.is_admin());

create table public.prediction_selections(id uuid primary key default gen_random_uuid(),prediction_id uuid not null references public.predictions(id),event_id text not null,market_key text not null,selection text not null,odds numeric not null check(odds>1),result public.prediction_result not null default 'pending',source_reference text,unique(prediction_id,event_id,market_key,selection));
alter table public.prediction_selections enable row level security;
revoke all on public.prediction_selections from anon,authenticated;
grant select on public.prediction_selections to authenticated;
create policy paid_selections on public.prediction_selections for select to authenticated using(public.is_admin() or exists(select 1 from public.predictions p join public.tipsters t on t.id=p.tipster_id where p.id=prediction_id and t.user_id=auth.uid()) or exists(select 1 from public.purchases pu where pu.prediction_id=prediction_selections.prediction_id and pu.user_id=auth.uid() and pu.payment_status='paid'));

create table public.disputes(id uuid primary key default gen_random_uuid(),purchase_id uuid not null unique references public.purchases(id),user_id uuid not null references public.profiles(id),reason text not null check(reason in ('late','content','payment','other')),details text not null check(length(details) between 10 and 2000),status text not null default 'open' check(status in ('open','approved','rejected','refunded')),resolution text,refund_reference text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table public.disputes enable row level security;
revoke all on public.disputes from anon,authenticated;
grant select,insert(purchase_id,user_id,reason,details) on public.disputes to authenticated;
create policy disputes_read on public.disputes for select to authenticated using(user_id=(select auth.uid()) or public.is_admin());
create policy disputes_insert on public.disputes for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.purchases p where p.id=purchase_id and p.user_id=auth.uid() and p.payment_status in ('paid','submitted')));
create index disputes_user on public.disputes(user_id);

create or replace function public.guard_prediction_record() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='DELETE' then
   if old.published_at is not null or old.match_date<=now() then raise exception 'Published history cannot be deleted'; end if;
   return old;
 end if;
 if TG_OP='INSERT' then
   if new.match_date<=now() then raise exception 'Start time must be in the future'; end if;
   if new.result<>'pending' then raise exception 'Results require a settlement record'; end if;
   return new;
 end if;
 if old.published_at is not null or old.match_date<=now() then
   if (to_jsonb(new)-'status'-'result'-'settled_at') is distinct from (to_jsonb(old)-'status'-'result'-'settled_at') then raise exception 'Published history is immutable'; end if;
   if new.status is distinct from old.status and not(old.status='published' and new.status='resulted') then raise exception 'Published history cannot be hidden'; end if;
 end if;
 if new.status='published' and (new.odds is null or new.odds<=1) then raise exception 'Valid odds required for publication'; end if;
 if new.status='published' and old.status<>'published' and (new.match_date<=now() or new.published_at is null) then raise exception 'Cannot publish after start'; end if;
 if new.result is distinct from old.result or new.status='resulted' then
   if not exists(select 1 from public.settlement_events where prediction_id=new.id and result=new.result) then raise exception 'Verified settlement evidence required'; end if;
 end if;
 return new;
end $$;
create trigger guard_prediction_record before insert or update or delete on public.predictions for each row execute function public.guard_prediction_record();

create or replace function public.notify_prediction_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='published' and old.status<>'published' then
 insert into public.notifications(user_id,kind,title_en,title_sw,href) select f.user_id,'new_prediction','New prediction from '||t.display_name,'Utabiri mpya kutoka kwa '||t.display_name,'/predictions/'||new.id from public.tipster_follows f join public.tipsters t on t.id=f.tipster_id where f.tipster_id=new.tipster_id;
 elsif new.result<>'pending' and old.result='pending' then
 insert into public.notifications(user_id,kind,title_en,title_sw,href) select user_id,'settlement','Prediction settled: '||new.result,'Utabiri umepata matokeo: '||new.result,'/predictions/'||new.id from public.purchases where prediction_id=new.id and payment_status='paid';
 end if; return new;
end $$;
create trigger prediction_activity after update on public.predictions for each row execute function public.notify_prediction_change();

create or replace function public.admin_settle_prediction(p_prediction_id uuid,p_result public.prediction_result,p_evidence text) returns void language plpgsql security definer set search_path='' as $$
declare p public.predictions;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if p_result='pending' or length(btrim(p_evidence))<10 then raise exception 'Result and evidence required'; end if;
 select * into p from public.predictions where id=p_prediction_id for update;
 if not found or p.status<>'published' or p.result<>'pending' or p.match_date>now() then raise exception 'Not eligible for settlement'; end if;
 insert into public.settlement_events(prediction_id,result,source,evidence,actor_user_id) values(p.id,p_result,'admin_review',p_evidence,auth.uid());
 update public.predictions set result=p_result,status='resulted',settled_at=now() where id=p.id;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'prediction_settled','prediction',p.id::text,jsonb_build_object('result',p_result,'evidence',p_evidence));
end $$;

-- Service-only result ingestion. Mapping must exist before publication; no free-text inference.
create or replace function public.ingest_selection_result(p_selection_id uuid,p_result public.prediction_result,p_reference text) returns void language plpgsql security definer set search_path='' as $$
declare s public.prediction_selections; p public.predictions; total integer; pending integer; losses integer; wins integer; final_result public.prediction_result;
begin
 if p_result='pending' or length(btrim(p_reference))<5 then raise exception 'Terminal result and provider reference required'; end if;
 select * into s from public.prediction_selections where id=p_selection_id;
 select * into p from public.predictions where id=s.prediction_id for update;
 if p.id is null or p.match_date>now() or p.status not in ('published','resulted') then raise exception 'Invalid prediction'; end if;
 if p.result<>'pending' then
   if s.result=p_result and s.source_reference=p_reference then return; end if;
   raise exception 'Already settled';
 end if;
 if s.result<>'pending' and s.result<>p_result then raise exception 'Result correction requires investigation'; end if;
 update public.prediction_selections set result=p_result,source_reference=p_reference where id=s.id;
 select count(*),count(*) filter(where result='pending'),count(*) filter(where result='lost'),count(*) filter(where result='won') into total,pending,losses,wins from public.prediction_selections where prediction_id=p.id;
 if total=p.selection_count and pending=0 then
   final_result:=case when losses>0 then 'lost'::public.prediction_result when wins=0 then 'void'::public.prediction_result else 'won'::public.prediction_result end;
   -- Partial void accumulators need adjusted provider odds: keep pending for manual review.
   if wins>0 and wins<total and losses=0 then return; end if;
   insert into public.settlement_events(prediction_id,result,source,evidence) values(p.id,final_result,'provider',p_reference);
   update public.predictions set result=final_result,status='resulted',settled_at=now() where id=p.id;
 end if;
end $$;

create or replace function public.tipster_performance() returns table(id uuid,display_name text,bio text,profile_image_url text,verification_status public.account_status,created_at timestamptz,total_predictions bigint,settled bigint,wins bigint,losses bigint,voids bigint,win_rate numeric,roi numeric,profit numeric,settled_30d bigint,roi_30d numeric,streak bigint,followers bigint,sales_30d bigint) language sql security definer set search_path='' as $$
 select t.id,t.display_name,t.bio,t.profile_image_url,t.verification_status,t.created_at,
 count(p.id),count(p.id) filter(where p.result in ('won','lost')),count(p.id) filter(where p.result='won'),count(p.id) filter(where p.result='lost'),count(p.id) filter(where p.result='void'),
 round(100.0*count(p.id) filter(where p.result='won')/nullif(count(p.id) filter(where p.result in ('won','lost')),0),1),
 round(100*sum(case when p.result='won' then p.odds-1 when p.result='lost' then -1 else 0 end)/nullif(count(p.id) filter(where p.result in ('won','lost')),0),1),
 sum(case when p.result='won' then p.odds-1 when p.result='lost' then -1 else 0 end),
 count(p.id) filter(where p.result in ('won','lost') and p.settled_at>now()-interval '30 days'),
 round(100*sum(case when p.settled_at>now()-interval '30 days' and p.result='won' then p.odds-1 when p.settled_at>now()-interval '30 days' and p.result='lost' then -1 else 0 end)/nullif(count(p.id) filter(where p.result in ('won','lost') and p.settled_at>now()-interval '30 days'),0),1),
 (select count(*) from public.predictions q where q.tipster_id=t.id and q.result='won' and q.settled_at>coalesce((select max(r.settled_at) from public.predictions r where r.tipster_id=t.id and r.result='lost'),'-infinity'::timestamptz)),
 (select count(*) from public.tipster_follows f where f.tipster_id=t.id),
 (select count(*) from public.purchases pu where pu.tipster_id=t.id and pu.payment_status='paid' and pu.created_at>now()-interval '30 days')
 from public.tipsters t left join public.predictions p on p.tipster_id=t.id and p.status in ('published','resulted') where t.verification_status='active' group by t.id;
$$;

create or replace function public.tipster_business_summary() returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid; answer jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select id into tid from public.tipsters where user_id=auth.uid();
 if tid is null then raise exception 'Tipster account required'; end if;
 select jsonb_build_object('sales',count(*),'gross',coalesce(sum(amount_tzs),0),'platform',coalesce(sum(platform_commission_tzs),0),'earnings',coalesce(sum(tipster_commission_tzs),0),'fees',coalesce(sum(processing_fee_tzs),0)) into answer from public.purchases where tipster_id=tid and payment_status='paid';
 return answer;
end $$;

create or replace function public.admin_resolve_dispute(p_id uuid,p_status text,p_resolution text,p_reference text default null) returns void language plpgsql security definer set search_path='' as $$
declare d public.disputes; p public.purchases; uid uuid;
begin
 if not public.is_admin() then raise exception 'Admin only'; end if;
 if length(btrim(p_resolution))<10 then raise exception 'Explain the decision'; end if;
 select * into d from public.disputes where id=p_id for update;
 if not found then raise exception 'Dispute not found'; end if;
 if not((d.status='open' and p_status in ('approved','rejected')) or (d.status='approved' and p_status='refunded')) then raise exception 'Invalid transition'; end if;
 if p_status='refunded' then
   if length(btrim(coalesce(p_reference,'')))<4 then raise exception 'Completed transfer reference required'; end if;
   select * into p from public.purchases where id=d.purchase_id for update;
   if p.payment_status='paid' then
     select user_id into uid from public.tipsters where id=p.tipster_id;
     -- Reverse the original liability. Available funds are used only if pending is insufficient.
     perform 1 from public.wallets where user_id=uid for update;
     if (select pending_balance_tzs+available_balance_tzs from public.wallets where user_id=uid)<p.tipster_commission_tzs then raise exception 'Reconcile tipster funds before recording refund'; end if;
     update public.wallets set available_balance_tzs=available_balance_tzs-greatest(p.tipster_commission_tzs-pending_balance_tzs,0),pending_balance_tzs=greatest(pending_balance_tzs-p.tipster_commission_tzs,0) where user_id=uid;
     insert into public.ledger_entries(purchase_id,user_id,entry_type,amount_tzs,metadata) values(p.id,uid,'refund_reversal',-p.tipster_commission_tzs,jsonb_build_object('reference',p_reference));
   end if;
   update public.purchases set payment_status='refunded' where id=d.purchase_id;
 end if;
 update public.disputes set status=p_status,resolution=p_resolution,refund_reference=p_reference,updated_at=now() where id=d.id;
 insert into public.notifications(user_id,kind,title_en,title_sw,href) values(d.user_id,'dispute','Your buyer protection request: '||p_status,'Ombi lako la ulinzi: '||p_status,'/protection');
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'dispute_'||p_status,'dispute',d.id::text,jsonb_build_object('resolution',p_resolution,'reference',p_reference));
end $$;

create or replace function public.wallet_activity() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.available_balance_tzs>old.available_balance_tzs then insert into public.notifications(user_id,kind,title_en,title_sw,href) values(new.user_id,'payout','Earnings are available for payout','Mapato yanapatikana kwa malipo','/tipster'); end if;
 return new;
end $$;
create trigger wallet_activity after update on public.wallets for each row execute function public.wallet_activity();

revoke execute on function public.guard_prediction_record(),public.notify_prediction_change(),public.wallet_activity(),public.admin_settle_prediction(uuid,public.prediction_result,text),public.ingest_selection_result(uuid,public.prediction_result,text),public.tipster_performance(),public.tipster_business_summary(),public.admin_resolve_dispute(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.tipster_performance() to anon,authenticated;
grant execute on function public.tipster_business_summary(),public.admin_settle_prediction(uuid,public.prediction_result,text),public.admin_resolve_dispute(uuid,text,text,text) to authenticated;
grant execute on function public.ingest_selection_result(uuid,public.prediction_result,text) to service_role;
grant all on public.prediction_selections,public.settlement_events,public.notifications,public.tipster_follows,public.disputes to service_role;
create or replace function public.get_prediction_protected_content(p_prediction_id uuid)
returns table(prediction_text text,betslip_code text) language sql security definer set search_path='' as $$
 select p.match_name || E'\n\n' || p.prediction_text,p.betslip_code from public.predictions p
 where p.id=p_prediction_id and auth.uid() is not null and (public.is_admin() or exists(select 1 from public.tipsters t where t.id=p.tipster_id and t.user_id=auth.uid()) or exists(select 1 from public.purchases pu where pu.prediction_id=p.id and pu.user_id=auth.uid() and pu.payment_status='paid'));
$$;
-- Prevent account deletion/cascade from erasing published evidence.
revoke delete on public.predictions from anon,authenticated;
commit;
