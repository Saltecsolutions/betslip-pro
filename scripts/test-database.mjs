import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
const db = new PGlite();
await db.exec(`
create role anon;create role authenticated;create role service_role bypassrls;
create schema auth;create schema storage;create schema extensions;create schema vault;create schema cron;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,phone_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}');
create table auth.sessions(id uuid primary key,user_id uuid);
create function auth.uid() returns uuid language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create function auth.role() returns text language sql stable as $$select current_user::text$$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key,bucket_id text,name text);
alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;
create table vault.decrypted_secrets(name text,decrypted_secret text);
create function vault.create_secret(secret text,name text) returns void language sql as $$insert into vault.decrypted_secrets values(name,secret)$$;
create function extensions.gen_random_bytes(n integer) returns bytea language sql as $$select decode(repeat('ab',n),'hex')$$;
create function cron.schedule(text,text,text) returns bigint language sql as $$select 1::bigint$$;
grant usage on schema public,auth,storage to anon,authenticated,service_role;
grant execute on all functions in schema auth to anon,authenticated,service_role;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
`);
const legacy=['002_marketplace_core.sql','002_manual_selcom_and_tipster_profiles.sql','003_paid_content_protection.sql','004_launch_security.sql','005_admin_and_advertiser.sql'];
const migrations=[...legacy,...(await readdir('supabase/migrations')).filter(x=>x.startsWith('20')).sort()];
for(const file of ['schema.sql',...migrations.map(x=>'migrations/'+x)]) {
 let sql=await readFile('supabase/'+file,'utf8');
 // PGlite supplies PostgreSQL itself; Supabase service integrations are stubbed above.
 sql=sql.replace(/^create extension[^;]*;/gmi,'');
 try {await db.exec(sql);}catch(e){console.error('MIGRATION FAILED',file,e.message);process.exit(1);}
}
console.log('PASS: full schema and migration chain');
const requested=process.argv.slice(2);
const tests=requested.length?requested:(await readdir('supabase/tests')).filter(x=>x.endsWith('.sql'));
let failed=0;
for(const file of tests){try{const results=await db.exec(await readFile('supabase/tests/'+file,'utf8'));console.log('PASS:',file);}catch(e){failed++;console.error('FAIL:',file,e.message);await db.exec('rollback;reset role;');}}
await db.close();process.exitCode=failed?1:0;
