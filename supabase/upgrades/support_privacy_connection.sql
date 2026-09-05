begin;
-- Compliance implementations live in the private schema; public functions are wrappers.
do $$declare definition text;begin
 definition:=pg_get_functiondef('compliance.export_my_data()'::regprocedure);
 if position('support_tickets' in definition)=0 then
 if position('return result;' in definition)=0 then raise exception 'Export insertion point missing';end if;
 definition:=replace(definition,'return result;', 'return result || jsonb_build_object(''support_tickets'',coalesce((select jsonb_agg(to_jsonb(t)-''request_key'') from support.tickets t where user_id=auth.uid()),''[]''),''support_messages'',coalesce((select jsonb_agg(to_jsonb(m)-''request_key''-''author_id'') from support.messages m join support.tickets t on t.id=m.ticket_id where t.user_id=auth.uid() and not m.internal),''[]''));');
 execute definition;
 end if;
 definition:=pg_get_functiondef('compliance.admin_restrict_account(uuid,text)'::regprocedure);
 if position('support.restrict_account' in definition)=0 then
 if position('delete from public.notifications' in definition)=0 then raise exception 'Restriction insertion point missing';end if;
 definition:=replace(definition,'delete from public.notifications','perform support.restrict_account(uid);'||chr(10)||' delete from public.notifications');
 execute definition;
 end if;
end $$;
commit;
