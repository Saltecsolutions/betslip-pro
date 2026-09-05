begin;
DO $block$ declare d text;begin
 select pg_get_functiondef('public.handle_new_user()'::regprocedure) into d;
 d:=replace(d,'insert into public.tipsters(user_id,display_name) values(new.id,display_name);','insert into public.tipsters(user_id,display_name) values(new.id,''New tipster'');');
 execute d;
end $block$;
commit;
