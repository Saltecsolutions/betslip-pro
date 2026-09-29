-- Account approval is sufficient for ordinary publication from the first slip.
-- Preserve consent, validation, risk holds, immutable records and server pricing.
create or replace function engine.submit(d jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid;pid uuid;reasons text[]:='{}'; n integer;start_at timestamptz;odds numeric;s jsonb; leg jsonb; mapped_odds numeric:=1;
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
