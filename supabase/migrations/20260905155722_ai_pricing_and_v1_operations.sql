begin;
create schema engine;
create index if not exists predictions_tipster_created on public.predictions(tipster_id,created_at desc);
create index if not exists purchases_tipster_created on public.purchases(tipster_id,created_at desc);
create index if not exists withdrawals_tipster_status on public.withdrawals(tipster_id,status);
revoke all on schema engine from public,anon,authenticated;
grant usage on schema engine to authenticated,service_role;

create table engine.prices (
 tipster_id uuid primary key references public.tipsters(id),
 price_tzs integer not null default 1000 check(price_tzs in (1000,1500,2000,3000,5000,7500,10000)),
 reviewed_at timestamptz not null default now(),
 decided_count integer not null default 0,
 reason_en text not null default 'Starter price: building verified history.',
 reason_sw text not null default 'Bei ya mwanzo: unajenga historia iliyothibitishwa.'
);
create table engine.price_reviews (
 id uuid primary key default gen_random_uuid(), tipster_id uuid not null references public.tipsters(id),
 previous_price integer not null, price_tzs integer not null, model_version text not null,
 signals jsonb not null, reason_en text not null, reason_sw text not null, created_at timestamptz not null default now()
);
create index price_reviews_tipster on engine.price_reviews(tipster_id,created_at desc);
create trigger price_reviews_immutable before update or delete on engine.price_reviews for each row execute function public.guard_evidence();
create table engine.submissions (
 prediction_id uuid primary key references public.predictions(id), reasons text[] not null,
 auto_published boolean not null, created_at timestamptz not null default now()
);
create table engine.economics (
 singleton boolean primary key default true check(singleton), wht_bps integer not null default 500 check(wht_bps between 0 and 3000)
);
insert into engine.economics default values;
alter table engine.prices enable row level security;
alter table engine.price_reviews enable row level security;
alter table engine.submissions enable row level security;
alter table engine.economics enable row level security;

-- All signals come from locked, evidenced results and actual orders. Voids do not earn reviews.
create function engine.signals(tid uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with results as (
 select p.id,p.result,s.created_at,least(coalesce(s.settled_odds,p.odds),100) odds,
 row_number() over(order by s.created_at desc,p.id) rn
 from public.predictions p join public.settlement_events s on s.prediction_id=p.id and s.result=p.result
 where p.tipster_id=tid and p.published_at is not null and p.status='resulted' and p.result in ('won','lost')
 ), perf as (
 select count(*) n,coalesce(avg((result='won')::int),0) win_rate,
 coalesce(avg(case when result='won' then odds-1 else -1 end),0) roi,
 coalesce(avg((result='won')::int) filter(where rn<=20),0) recent_form,
 coalesce(avg(case when result='won' then odds-1 else -1 end) filter(where rn<=20),0) recent_roi,
 coalesce(avg(odds),0) odds_difficulty,
 coalesce(stddev_pop(case when result='won' then odds-1 else -1 end),0) volatility from results
 ), orders as (select * from public.purchases where tipster_id=tid and created_at>=now()-interval '90 days'),
 buyers as (select user_id,count(*) n from orders where payment_status='paid' group by user_id),
 market as (select count(*) filter(where payment_status='paid') paid,
 coalesce(count(*) filter(where payment_status='paid')::numeric/nullif(count(*) filter(where payment_status<>'refunded'),0),0) demand,
 coalesce(count(*) filter(where payment_status='refunded')::numeric/nullif(count(*) filter(where payment_status in ('paid','refunded')),0),0) refund_rate from orders)
 select jsonb_build_object('sample_size',n,'win_rate',win_rate,'roi',roi,'recent_form',recent_form,'recent_roi',recent_roi,
 'odds_difficulty',odds_difficulty,'consistency',1/(1+volatility),'paid_orders',paid,'demand',demand,'refund_rate',refund_rate,
 'repeat_buyers',coalesce((select count(*) filter(where n>=2)::numeric/nullif(count(*),0) from buyers),0),
 'sell_through',coalesce((select count(*) filter(where exists(select 1 from orders o where o.prediction_id=p.id and o.payment_status='paid'))::numeric/nullif(count(*),0) from public.predictions p where tipster_id=tid and published_at>=now()-interval '90 days'),0),
 'rating',coalesce((select avg(r.rating) from public.purchase_ratings r join orders o on o.id=r.purchase_id where o.payment_status='paid'),0),
 'rating_count',(select count(*) from public.purchase_ratings r join orders o on o.id=r.purchase_id where o.payment_status='paid'),
 'dispute_rate',coalesce((select count(distinct d.purchase_id)::numeric/nullif((select count(*) from orders where payment_status in ('paid','refunded')),0) from public.disputes d join orders o on o.id=d.purchase_id where d.status in ('open','approved','refunded')),0),
 'hold',coalesce((select on_hold from public.tipster_reviews where tipster_id=tid),false)) from perf cross join market;
$$;

-- Versioned, deterministic multi-signal model. Scores cannot bypass evidence, risk or step caps.
create function engine.target_price(s jsonb) returns integer language plpgsql immutable set search_path='' as $$
declare n integer:=(s->>'sample_size')::integer; score numeric; target integer;
begin
 if n<20 or coalesce((s->>'hold')::boolean,true) then return 1000; end if;
 if (s->>'roi')::numeric<=0 or (s->>'recent_roi')::numeric<=0 or (s->>'refund_rate')::numeric>0.10 or (s->>'dispute_rate')::numeric>0.10 then return 1000; end if;
 score:=20*least(1,greatest(0,(s->>'roi')::numeric))
 +15*(s->>'win_rate')::numeric+15*(s->>'recent_form')::numeric
 +5*least(1,(s->>'odds_difficulty')::numeric/5)+10*(s->>'consistency')::numeric
 +10*(s->>'repeat_buyers')::numeric+5*(s->>'sell_through')::numeric+5*(s->>'demand')::numeric
 +10*case when (s->>'rating_count')::integer>=5 then (s->>'rating')::numeric/5 else 0 end
 +5*least(1,n::numeric/200)-50*((s->>'dispute_rate')::numeric+(s->>'refund_rate')::numeric);
 target:=case when score>=85 then 10000 when score>=75 then 7500 when score>=65 then 5000 when score>=55 then 3000 when score>=45 then 2000 when score>=35 then 1500 else 1000 end;
 return least(target,case when n<40 then 2000 when n<75 then 3000 when n<150 then 5000 when n<200 then 7500 else 10000 end,
 case when (s->>'paid_orders')::integer<5 then 1000 when (s->>'paid_orders')::integer<20 then 2000 else 10000 end);
end $$;

create function engine.review_price(tid uuid) returns engine.prices language plpgsql security definer set search_path='' as $$
declare p engine.prices; s jsonb; target integer; next_price integer; bands integer[]:=array[1000,1500,2000,3000,5000,7500,10000]; idx integer; why_en text; why_sw text;
begin
 insert into engine.prices(tipster_id) values(tid) on conflict do nothing;
 select * into p from engine.prices where tipster_id=tid for update;
 s:=engine.signals(tid);
 if now()<p.reviewed_at+interval '24 hours' or (s->>'sample_size')::integer<p.decided_count+5 then return p;end if;
 target:=engine.target_price(s);idx:=array_position(bands,p.price_tzs);
 next_price:=case when target>p.price_tzs then least(target,bands[least(7,idx+1)]) when target<p.price_tzs then greatest(target,bands[greatest(1,idx-1)]) else p.price_tzs end;
 why_en:=format('%s verified results; ROI %s%%; recent wins %s%%. %s',s->>'sample_size',round(100*(s->>'roi')::numeric,1),round(100*(s->>'recent_form')::numeric,1),case when target=1000 then 'Evidence or risk guardrails limit pricing.' else 'Performance and paid demand support this band.' end);
 why_sw:=format('Matokeo %s yaliyothibitishwa; ROI %s%%; ushindi wa karibuni %s%%. %s',s->>'sample_size',round(100*(s->>'roi')::numeric,1),round(100*(s->>'recent_form')::numeric,1),case when target=1000 then 'Ushahidi au viwango vya hatari vinadhibiti bei.' else 'Utendaji na mahitaji yaliyolipiwa yanaunga mkono kiwango hiki.' end);
 insert into engine.price_reviews(tipster_id,previous_price,price_tzs,model_version,signals,reason_en,reason_sw) values(tid,p.price_tzs,next_price,'v1.0',s,why_en,why_sw);
 update engine.prices set price_tzs=next_price,reviewed_at=now(),decided_count=(s->>'sample_size')::integer,reason_en=why_en,reason_sw=why_sw where tipster_id=tid returning * into p;
 return p;
end $$;
create function engine.my_price() returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid;p engine.prices;s jsonb;
begin
 select id into tid from public.tipsters where user_id=auth.uid();if tid is null then raise exception 'Tipster account required';end if;
 p:=engine.review_price(tid);s:=engine.signals(tid);
 return to_jsonb(p)||jsonb_build_object('next_review_at',p.reviewed_at+interval '24 hours','results_remaining',greatest(0,p.decided_count+5-(s->>'sample_size')::integer),'model_version','v1.0');
end $$;
create function public.my_ai_price() returns jsonb language sql security invoker set search_path='' as $$select engine.my_price();$$;

-- Block every client write path for price and publication. Only the submission RPC accepts content.
revoke insert,update,delete on public.predictions from anon,authenticated;
-- Column grants survive table-level REVOKE; remove any inherited column write grants too.
do $$declare r record;begin for r in select column_name from information_schema.columns where table_schema='public' and table_name='predictions' loop execute format('revoke insert(%I),update(%I) on public.predictions from anon,authenticated',r.column_name,r.column_name);end loop;end $$;
create function engine.assign_price() returns trigger language plpgsql security definer set search_path='' as $$
declare p engine.prices;
begin
 if TG_OP='INSERT' or (old.published_at is null and new.status='published') then
 p:=engine.review_price(new.tipster_id);new.price_tzs:=p.price_tzs;
 elsif new.price_tzs is distinct from old.price_tzs then raise exception 'Price is set by Betslip Pro AI';end if;
 return new;
end $$;
create trigger ai_price before insert or update on public.predictions for each row execute function engine.assign_price();

create function engine.submit(d jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid;pid uuid;reasons text[]:='{}'; reviewed integer; n integer;start_at timestamptz;odds numeric;s jsonb; leg jsonb; mapped_odds numeric:=1;
begin
 select t.id into tid from public.tipsters t join public.profiles u on u.id=t.user_id where t.user_id=auth.uid() and t.verification_status='active' and u.status='active' for update of t;
 if tid is null or not compliance.accepted(auth.uid(),true) then raise exception 'Active tipster and seller agreement required';end if;
 start_at:=(d->>'match_date')::timestamptz;odds:=(d->>'odds')::numeric;n:=(d->>'selection_count')::integer;
 if start_at is null or start_at<=now() or odds is null or odds='NaN'::numeric or odds<=1 or odds>999999 or n is null or n not between 1 and 50
 or length(btrim(coalesce(d->>'title',''))) not between 3 and 120 or length(btrim(coalesce(d->>'analysis',''))) not between 20 and 1500
 or length(btrim(coalesce(d->>'match_name',''))) not between 3 and 500 or length(btrim(coalesce(d->>'prediction_text',''))) not between 5 and 10000
 or coalesce(d->>'sport','') not in ('Football','Basketball','Tennis') or coalesce(d->>'bookmaker','') not in ('BetPawa','SportyBet','Betway','1xBet','Other')
 or length(btrim(coalesce(d->>'betslip_code',''))) not between 1 and 100 then raise exception 'Complete valid content and future kickoff required';end if;
 if exists(select 1 from public.predictions where tipster_id=tid and created_at>now()-interval '1 minute') then raise exception 'Please wait a minute before submitting again';end if;
 select count(*) into reviewed from public.predictions p where p.tipster_id=tid and p.published_at is not null and exists(select 1 from public.audit_logs a where a.entity_id=p.id::text and a.action='prediction_review_decision' and a.metadata->>'decision'='published');
 if reviewed<5 then reasons:=array_append(reasons,'probation');end if;
 if not exists(select 1 from compliance.kyc_records where user_id=auth.uid() and review_status='verified') then reasons:=array_append(reasons,'identity_review');end if;
 s:=engine.signals(tid);
 if (s->>'hold')::boolean or (s->>'dispute_rate')::numeric>0.10 or (s->>'refund_rate')::numeric>0.10 then reasons:=array_append(reasons,'integrity_hold');end if;
 if (s->>'sample_size')::integer>=20 and ((s->>'win_rate')::numeric>=0.90 or (s->>'roi')::numeric>=1) then reasons:=array_append(reasons,'unusual_performance');end if;
 if start_at<now()+interval '15 minutes' then reasons:=array_append(reasons,'near_kickoff');end if;
 if odds>100 or n>20 then reasons:=array_append(reasons,'odds_or_size');end if;
 if exists(select 1 from public.predictions where tipster_id=tid and match_date=start_at and (lower(btrim(betslip_code))=lower(btrim(d->>'betslip_code')) or lower(btrim(prediction_text))=lower(btrim(d->>'prediction_text')))) then reasons:=array_append(reasons,'duplicate');end if;
 insert into public.predictions(tipster_id,title,sport,league,analysis,confidence,match_name,prediction_text,betslip_code,bookmaker,odds,selection_count,match_date,category,status)
 values(tid,btrim(d->>'title'),d->>'sport',left(d->>'league',200),d->>'analysis',nullif(d->>'confidence','')::smallint,d->>'match_name',d->>'prediction_text',d->>'betslip_code',d->>'bookmaker',odds,n,start_at,case when n=1 then 'single' else 'betslip' end,'pending') returning id into pid;
 if d ? 'selections' and d->'selections'<>'[]'::jsonb then
 if jsonb_typeof(d->'selections')<>'array' or jsonb_array_length(d->'selections')<>n then raise exception 'Every selection must be mapped';end if;
 for leg in select value from jsonb_array_elements(d->'selections') loop
 if length(btrim(coalesce(leg->>'event_id',''))) not between 1 and 100 or length(btrim(coalesce(leg->>'market_key',''))) not between 1 and 100 or length(btrim(coalesce(leg->>'selection',''))) not between 1 and 200
 or (leg->>'odds')::numeric is null or (leg->>'odds')::numeric='NaN'::numeric or (leg->>'odds')::numeric<=1 or (leg->>'odds')::numeric>1000 then raise exception 'Valid provider event, market, selection and odds required';end if;
 mapped_odds:=mapped_odds*(leg->>'odds')::numeric;
 insert into public.prediction_selections(prediction_id,event_id,market_key,selection,odds) values(pid,btrim(leg->>'event_id'),btrim(leg->>'market_key'),btrim(leg->>'selection'),(leg->>'odds')::numeric);
 end loop;
 if abs(round(mapped_odds,2)-odds)>0.01 then raise exception 'Selection odds must match total odds';end if;
 if (select count(distinct event_id) from public.prediction_selections where prediction_id=pid)<>n then reasons:=array_append(reasons,'correlated_selections');end if;
 end if;
 insert into engine.submissions values(pid,reasons,cardinality(reasons)=0,now());
 if cardinality(reasons)=0 then update public.predictions set status='published' where id=pid;end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'automatic_validation','prediction',pid::text,jsonb_build_object('reasons',reasons,'auto_published',cardinality(reasons)=0));
 return jsonb_build_object('id',pid,'status',case when cardinality(reasons)=0 then 'published' else 'pending' end,'reasons',reasons);
end $$;
create function public.submit_prediction(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select engine.submit(p_data);$$;

-- Capture allocation on each order; never recalculate historical tax from current settings.
alter table public.purchases add column wht_bps integer not null default 500 check(wht_bps between 0 and 3000),
 add column wht_allocation_tzs integer not null default 0,
 add column platform_net_tzs integer not null default 0;
update public.purchases set wht_allocation_tzs=round(amount_tzs*0.05),platform_net_tzs=platform_commission_tzs-round(amount_tzs*0.05);
alter table public.purchases add constraint platform_allocation_check check(wht_allocation_tzs>=0 and platform_net_tzs>=0 and wht_allocation_tzs+platform_net_tzs=platform_commission_tzs);
create function engine.allocate_sale() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
 select wht_bps into new.wht_bps from engine.economics where singleton;
 new.platform_commission_tzs:=round(new.amount_tzs*0.30);
 new.tipster_commission_tzs:=new.amount_tzs-new.platform_commission_tzs;
 new.wht_allocation_tzs:=round(new.amount_tzs*new.wht_bps/10000.0);
 new.platform_net_tzs:=new.platform_commission_tzs-new.wht_allocation_tzs;
 elsif (new.amount_tzs,new.tipster_id,new.user_id,new.prediction_id,new.wht_bps,new.wht_allocation_tzs,new.platform_net_tzs,new.platform_commission_tzs,new.tipster_commission_tzs)
 is distinct from (old.amount_tzs,old.tipster_id,old.user_id,old.prediction_id,old.wht_bps,old.wht_allocation_tzs,old.platform_net_tzs,old.platform_commission_tzs,old.tipster_commission_tzs) then raise exception 'Order economics and ownership are immutable';end if;
 return new;
end $$;
create trigger sale_allocation before insert or update on public.purchases for each row execute function engine.allocate_sale();
create function engine.allocation_ledger() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.payment_status='paid' and old.payment_status<>'paid' then
 insert into public.ledger_entries(purchase_id,entry_type,amount_tzs) values(new.id,'platform_wht_allocation',new.wht_allocation_tzs),(new.id,'platform_net_allocation',new.platform_net_tzs);
 elsif new.payment_status='refunded' and old.payment_status='paid' then
 insert into public.ledger_entries(purchase_id,entry_type,amount_tzs) values(new.id,'platform_commission_reversal',-new.platform_commission_tzs),(new.id,'platform_wht_reversal',-new.wht_allocation_tzs),(new.id,'platform_net_reversal',-new.platform_net_tzs);
 end if;return new;
end $$;
create trigger allocation_ledger after update on public.purchases for each row execute function engine.allocation_ledger();
-- Partner access is aggregate-only and requires the confirmed account email already used by this project.
create table engine.revenue_readers(email text primary key,enabled boolean not null default true);
alter table engine.revenue_readers enable row level security;
insert into engine.revenue_readers(email) values('jdaking08@gmail.com');
create function engine.can_read_revenue() returns boolean language sql stable security definer set search_path='' as $$
 select compliance.can('finance') or exists(select 1 from auth.users u join public.profiles p on p.id=u.id join engine.revenue_readers r on r.email=lower(u.email) where u.id=auth.uid() and u.email_confirmed_at is not null and p.status='active' and r.enabled and compliance.accepted(u.id));
$$;
create function public.revenue_access() returns boolean language sql security invoker set search_path='' as $$select engine.can_read_revenue();$$;
create function engine.finance_summary() returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;
begin
 if not engine.can_read_revenue() then raise exception 'Finance permission required';end if;
 select jsonb_build_object('gross',coalesce(sum(amount_tzs) filter(where payment_status='paid'),0),
 'tipster',coalesce(sum(tipster_commission_tzs) filter(where payment_status='paid'),0),
 'platform',coalesce(sum(platform_commission_tzs) filter(where payment_status='paid'),0),
 'wht',coalesce(sum(wht_allocation_tzs) filter(where payment_status='paid'),0),
 'platformNet',coalesce(sum(platform_net_tzs) filter(where payment_status='paid'),0),
 'fees',coalesce(sum(processing_fee_tzs) filter(where payment_verified_at is not null),0),
 'refunds',coalesce(sum(amount_tzs) filter(where payment_status='refunded' and payment_verified_at is not null),0),
 'awaiting',coalesce(sum(amount_tzs) filter(where payment_status='submitted'),0),
 'payouts',coalesce((select sum(amount_tzs) from public.withdrawals where status='paid'),0),
 'wallet_pending',coalesce((select sum(pending_balance_tzs) from public.wallets),0),
 'wallet_available',coalesce((select sum(available_balance_tzs) from public.wallets),0)) into r from public.purchases;
 insert into public.audit_logs(actor_user_id,action,entity_type) values(auth.uid(),'finance_summary_read','finance');return r;
end $$;
create function public.platform_revenue_summary() returns jsonb language sql security invoker set search_path='' as $$select engine.finance_summary();$$;
create function engine.configure_wht(bps integer,reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not compliance.can('configuration') or not compliance.can('finance') then raise exception 'Finance and configuration permission required';end if;
 if bps is null or bps not between 0 and 3000 or length(btrim(coalesce(reason,'')))<10 then raise exception 'Valid allocation and reason required';end if;
 update engine.economics set wht_bps=bps where singleton;
 insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(auth.uid(),'wht_allocation_changed','finance',jsonb_build_object('bps',bps,'reason',reason));
end $$;
create function public.configure_wht_allocation(p_bps integer,p_reason text) returns void language sql security invoker set search_path='' as $$select engine.configure_wht(p_bps,p_reason);$$;

-- Reserve funds when a withdrawal is requested, and consume or release the reservation once.
alter table public.withdrawals add column payout_reference text, add column funds_reserved boolean not null default false, add column request_id uuid;
create unique index withdrawal_request_unique on public.withdrawals(tipster_id,request_id);
create unique index payout_reference_unique on public.withdrawals(lower(btrim(payout_reference))) where payout_reference is not null;
create function engine.withdraw(amount integer,method text,account text,request_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare tid uuid;wid uuid;prior public.withdrawals;
begin
 select id into tid from public.tipsters where user_id=auth.uid() and verification_status='active';
 if tid is null or not compliance.accepted(auth.uid(),true) then raise exception 'Active seller account required';end if;
 if amount is null or amount<1000 or length(btrim(coalesce(account,''))) not between 6 and 100 or method is null or method not in ('mobile_money','bank') then raise exception 'Minimum TZS 1,000 and valid payout details required';end if;
 if request_key is null then raise exception 'Request key required';end if;
 perform 1 from public.wallets where user_id=auth.uid() for update;
 select * into prior from public.withdrawals where tipster_id=tid and request_id=request_key;
 if found then
 if prior.amount_tzs<>amount or prior.payment_method<>method or prior.account_number<>btrim(account) then raise exception 'Request key already used for different payout';end if;
 return prior.id;end if;
 update public.wallets set available_balance_tzs=available_balance_tzs-amount,updated_at=now() where user_id=auth.uid() and available_balance_tzs>=amount;
 if not found then raise exception 'Insufficient available balance';end if;
 insert into public.withdrawals(tipster_id,amount_tzs,payment_method,account_number,funds_reserved,request_id) values(tid,amount,method,btrim(account),true,request_key) returning id into wid;
 insert into public.ledger_entries(user_id,entry_type,amount_tzs,metadata) values(auth.uid(),'withdrawal_reserved',-amount,jsonb_build_object('withdrawal_id',wid));return wid;
end $$;
create function public.request_withdrawal(p_amount integer,p_method text,p_account text,p_request_id uuid default gen_random_uuid()) returns uuid language sql security invoker set search_path='' as $$select engine.withdraw(p_amount,p_method,p_account,p_request_id);$$;
create function engine.payouts() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not compliance.can('finance') then raise exception 'Finance permission required';end if;
 insert into public.audit_logs(actor_user_id,action,entity_type) values(auth.uid(),'payout_details_read','finance');
 return (select coalesce(jsonb_agg(r),'[]') from (select w.*,t.display_name from public.withdrawals w join public.tipsters t on t.id=w.tipster_id order by w.created_at desc limit 200) r);
end $$;
create function public.payout_queue() returns jsonb language sql security invoker set search_path='' as $$select engine.payouts();$$;
create function engine.finish_payout(wid uuid,decision text,reference text) returns void language plpgsql security definer set search_path='' as $$
declare w public.withdrawals;uid uuid;
begin
 if not compliance.can('finance') then raise exception 'Finance permission required';end if;
 if decision is null or decision not in ('paid','rejected') or length(btrim(coalesce(reference,'')))<5 then raise exception 'Final decision and reference or reason required';end if;
 select * into w from public.withdrawals where id=wid for update;
 if not found or w.status not in ('pending','approved') then raise exception 'Pending withdrawal required';end if;
 if not w.funds_reserved then raise exception 'Legacy payout requires reservation reconciliation';end if;
 select user_id into uid from public.tipsters where id=w.tipster_id;
 update public.wallets set available_balance_tzs=available_balance_tzs+case when decision='rejected' then w.amount_tzs else 0 end,total_withdrawn_tzs=total_withdrawn_tzs+case when decision='paid' then w.amount_tzs else 0 end,updated_at=now() where user_id=uid;
 update public.withdrawals set status=decision::public.withdrawal_status,payout_reference=case when decision='paid' then btrim(reference) end,admin_note=reference where id=wid;
 insert into public.ledger_entries(user_id,entry_type,amount_tzs,metadata) values(uid,'withdrawal_'||decision,w.amount_tzs,jsonb_build_object('withdrawal_id',wid,'reference',reference));
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'withdrawal_'||decision,'withdrawal',wid::text,jsonb_build_object('reference',reference));
end $$;
create function public.finish_payout(p_id uuid,p_decision text,p_reference text) returns void language sql security invoker set search_path='' as $$select engine.finish_payout(p_id,p_decision,p_reference);$$;

-- Reviewers see integrity signals, never buyer identities or payment references.
create function engine.queues(queue text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not moderation.can_review() or not compliance.accepted(auth.uid()) then raise exception 'Review permission required';end if;
 insert into public.audit_logs(actor_user_id,action,entity_type,metadata) values(auth.uid(),'exception_queue_read','prediction',jsonb_build_object('queue',queue));
 if queue='reported' then
 return (select coalesce(jsonb_agg(r),'[]') from (select p.id,p.title,t.display_name,count(*) reports,'buyer_report' reason from public.disputes d join public.purchases pu on pu.id=d.purchase_id join public.predictions p on p.id=pu.prediction_id join public.tipsters t on t.id=p.tipster_id where d.status in ('open','approved') and t.user_id<>auth.uid() group by p.id,t.display_name order by count(*) desc limit 100) r);
 elsif queue='suspicious' then
 return (select coalesce(jsonb_agg(r),'[]') from (select p.id,p.title,t.display_name,array_to_string(s.reasons,', ') reason from engine.submissions s join public.predictions p on p.id=s.prediction_id join public.tipsters t on t.id=p.tipster_id where s.reasons&&array['integrity_hold','unusual_performance','duplicate','odds_or_size'] and p.status='pending' and t.user_id<>auth.uid()
 union all select p.id,p.title,t.display_name,'overdue_settlement' reason from public.predictions p join public.tipsters t on t.id=p.tipster_id where p.status='published' and p.result='pending' and p.match_date<now()-interval '48 hours' and t.user_id<>auth.uid() limit 100) r);
 end if;raise exception 'Unknown queue';
end $$;
create function public.exception_queue(p_queue text) returns jsonb language sql security invoker set search_path='' as $$select engine.queues(p_queue);$$;

-- Serialize on the parent BEFORE rereading a selection, so simultaneous callbacks are idempotent.
create or replace function public.ingest_selection_result(p_selection_id uuid,p_result public.prediction_result,p_reference text) returns void language plpgsql security definer set search_path='' as $$
declare s public.prediction_selections;p public.predictions;total integer;pending integer;losses integer;wins integer;final_result public.prediction_result;effective numeric;
begin
 if p_result is null or p_result='pending' or length(btrim(coalesce(p_reference,''))) not between 5 and 500 then raise exception 'Terminal result and provider reference required';end if;
 select pr.* into p from public.predictions pr join public.prediction_selections se on se.prediction_id=pr.id where se.id=p_selection_id for update of pr;
 select * into s from public.prediction_selections where id=p_selection_id;
 if p.id is null or p.match_date>now() or p.status not in ('published','resulted') then raise exception 'Invalid prediction';end if;
 if s.result<>'pending' then
 if s.result=p_result and s.source_reference=p_reference then return;end if;
 raise exception 'Result correction requires investigation';end if;
 if p.result<>'pending' then raise exception 'Already settled';end if;
 update public.prediction_selections set result=p_result,source_reference=p_reference where id=s.id;
 select count(*),count(*) filter(where result='pending'),count(*) filter(where result='lost'),count(*) filter(where result='won'),exp(coalesce(sum(ln(odds)) filter(where result='won'),0)) into total,pending,losses,wins,effective from public.prediction_selections where prediction_id=p.id;
 if total=p.selection_count and pending=0 then
 final_result:=case when losses>0 then 'lost'::public.prediction_result when wins=0 then 'void'::public.prediction_result else 'won'::public.prediction_result end;
 effective:=case when final_result='void' then 1 when final_result='lost' then p.odds else round(effective,2) end;
 if effective>p.odds+0.01 then raise exception 'Mapped odds exceed published odds';end if;
 insert into public.settlement_events(prediction_id,result,source,evidence,settled_odds) values(p.id,final_result,'provider',p_reference,effective);
 update public.predictions set result=final_result,status='resulted',settled_at=now() where id=p.id;
 end if;
end $$;
-- Repricing is also evaluated after settlement; the daily job catches elapsed-time eligibility.
create function engine.on_result() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.result<>old.result then perform engine.review_price(new.tipster_id);end if;return new;end $$;
create trigger ai_result_review after update on public.predictions for each row execute function engine.on_result();
create function engine.daily_reviews() returns void language plpgsql security definer set search_path='' as $$
declare t record;begin for t in select id from public.tipsters where verification_status='active' order by id loop perform engine.review_price(t.id);end loop;end $$;

grant select(wht_bps,wht_allocation_tzs,platform_net_tzs) on public.purchases to authenticated;
revoke all on all tables in schema engine from public,anon,authenticated,service_role;
revoke all on all functions in schema engine from public,anon,authenticated,service_role;
grant execute on function engine.my_price(),engine.submit(jsonb),engine.finance_summary(),engine.configure_wht(integer,text),engine.withdraw(integer,text,text,uuid),engine.payouts(),engine.finish_payout(uuid,text,text),engine.queues(text) to authenticated;
grant execute on function engine.daily_reviews() to service_role;
revoke all on function public.my_ai_price(),public.submit_prediction(jsonb),public.platform_revenue_summary(),public.configure_wht_allocation(integer,text),public.request_withdrawal(integer,text,text,uuid),public.payout_queue(),public.finish_payout(uuid,text,text),public.exception_queue(text) from public,anon,authenticated;
grant execute on function public.my_ai_price(),public.submit_prediction(jsonb),public.platform_revenue_summary(),public.configure_wht_allocation(integer,text),public.request_withdrawal(integer,text,text,uuid),public.payout_queue(),public.finish_payout(uuid,text,text),public.exception_queue(text) to authenticated;
revoke all on function public.ingest_selection_result(uuid,public.prediction_result,text) from public,anon,authenticated;
grant execute on function public.ingest_selection_result(uuid,public.prediction_result,text) to service_role;
-- pg_cron is already installed by the existing admin-alert schedule migration.
do $$begin if exists(select 1 from pg_extension where extname='pg_cron') then perform cron.schedule('betslip-ai-pricing','15 0 * * *','select engine.daily_reviews()');end if;end $$;
-- Extend the existing audited payment reader with immutable allocation snapshots.
do $$declare definition text;begin
 select pg_get_functiondef('compliance.admin_compliance_read(text,text)'::regprocedure) into definition;
 definition:=replace(definition,'id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,payment_reference','id,amount_tzs,wht_bps,wht_allocation_tzs,platform_net_tzs,platform_commission_tzs,tipster_commission_tzs,payment_reference');
 execute definition;
end $$;
create function engine.balances() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not compliance.can('finance') then raise exception 'Finance permission required';end if;
 insert into public.audit_logs(actor_user_id,action,entity_type) values(auth.uid(),'wallet_balances_read','finance');
 return (select coalesce(jsonb_agg(r),'[]') from (select t.user_id,t.display_name,w.pending_balance_tzs,w.available_balance_tzs from public.wallets w join public.tipsters t on t.user_id=w.user_id where w.pending_balance_tzs>0 or w.available_balance_tzs>0 order by t.id limit 200) r);
end $$;
create function public.finance_wallet_balances() returns jsonb language sql security invoker set search_path='' as $$select engine.balances();$$;
revoke all on function engine.balances(),public.finance_wallet_balances() from public,anon,authenticated;
grant execute on function engine.balances(),public.finance_wallet_balances() to authenticated;
do $$declare definition text;begin
 select pg_get_functiondef('public.make_tipster_earnings_available(uuid,bigint)'::regprocedure) into definition;
 definition:=replace(definition,'end;'||chr(10)||'$function$', 'insert into public.ledger_entries(user_id,entry_type,amount_tzs) values(p_tipster_user_id,''earnings_released'',p_amount_tzs);'||chr(10)||'insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata) values(auth.uid(),''earnings_released'',''wallet'',p_tipster_user_id::text,jsonb_build_object(''amount_tzs'',p_amount_tzs));'||chr(10)||'end;'||chr(10)||'$function$');
 execute definition;
end $$;
do $$declare definition text;begin
 select pg_get_functiondef('public.tipster_business_summary()'::regprocedure) into definition;
 definition:=replace(definition,'''sales'',count(*)', '''reserved'',(select coalesce(sum(amount_tzs),0) from public.withdrawals where tipster_id=tid and funds_reserved and status in (''pending'',''approved'')),''sales'',count(*)');
 execute definition;
end $$;

-- Expired submissions may still be rejected; only publication requires future kickoff.
do $$declare definition text;begin
 select pg_get_functiondef('moderation.api(text,jsonb)'::regprocedure) into definition;
 definition:=replace(definition,'if p.match_date<=now() then','if decision=''published'' and p.match_date<=now() then');
 definition:=replace(definition,'q.odds,q.status,t.display_name','q.odds,q.status,t.display_name,coalesce((select s.reasons from engine.submissions s where s.prediction_id=q.id),array[''legacy_review'']) review_reasons');
 execute definition;
end $$;

revoke all on function engine.can_read_revenue(),public.revenue_access() from public,anon,authenticated;
grant execute on function engine.can_read_revenue(),public.revenue_access() to authenticated;

commit;
