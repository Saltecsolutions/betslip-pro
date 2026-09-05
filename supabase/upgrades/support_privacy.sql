begin;
create index support_message_author_rate on support.messages(author_id,created_at);
create function support.restrict_account(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 -- Called only by the existing authorized privacy restriction workflow.
 update support.tickets set email_updates=false where user_id=p_user;
 update admin_alerts.outbox o set summary=summary-'email',status=case when status in ('pending','sending') then 'failed' else status end,
 error_code=case when status in ('pending','sending') then 'privacy_restriction' else error_code end,lease_token=null,lease_until=null
 where kind='support_customer' and exists(select 1 from support.tickets t where t.user_id=p_user and t.id::text=o.summary->>'ticket_id');
 update support.messages m set body='Removed after privacy request / Imeondolewa baada ya ombi la faragha',author_id=null
 where exists(select 1 from support.tickets t where t.id=m.ticket_id and t.user_id=p_user and t.purchase_id is null and t.dispute_id is null and t.category not in ('payment','content','refund'));
 update support.tickets set subject='Removed after privacy request / Imeondolewa baada ya ombi la faragha',status='closed',assigned_to=null,due_at=null,redacted_at=now(),updated_at=now()
 where user_id=p_user and purchase_id is null and dispute_id is null and category not in ('payment','content','refund');
end $$;
revoke all on function support.restrict_account(uuid) from public,anon,authenticated,service_role;
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.admin_restrict_account(uuid,text)'::regprocedure);
 definition:=replace(definition,'delete from public.notifications where user_id=uid;', 'perform support.restrict_account(uid);'||chr(10)||' delete from public.notifications where user_id=uid;');
 execute definition;
end $$;
-- Revoked handlers must not continue receiving new ticket assignments or updates.
create or replace function support.notify_agent(p_ticket uuid) returns void language plpgsql security definer set search_path='' as $$
declare t support.tickets;
begin
 select * into strict t from support.tickets where id=p_ticket;
 if t.assigned_to is null or not support.eligible(t.assigned_to,t.category) then
 update support.tickets set assigned_to=support.assign(category) where id=p_ticket returning * into t;
 end if;
 if t.assigned_to is not null then insert into public.notifications(user_id,kind,title_en,title_sw,href) values(t.assigned_to,'support','Support ticket BP-'||t.number||' needs attention','Ticket BP-'||t.number||' inahitaji hatua','/support/team/'||t.id);end if;
end $$;
commit;
