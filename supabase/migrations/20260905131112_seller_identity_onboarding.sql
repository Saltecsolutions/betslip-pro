begin;
DO $block$ declare d text; begin
 select pg_get_functiondef('compliance.accept_policies(text,text,boolean)'::regprocedure) into d;
 d:=replace(d,'update public.profiles set age_verified=true where id=auth.uid();','update public.profiles set age_verified=true where id=auth.uid(); if p_seller then insert into public.tipsters(user_id,display_name) values(auth.uid(),''New tipster'') on conflict(user_id) do nothing; update public.profiles set requested_role=''tipster'' where id=auth.uid() and role=''bettor''; end if;');
 execute d;
end $block$;
commit;
