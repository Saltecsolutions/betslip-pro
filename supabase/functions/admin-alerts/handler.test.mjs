import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler,emailFor} from './handler.mjs';
const token='a'.repeat(64);
const item={id:'event-one',kind:'privacy',lease_token:'lease-one'};
const env=name=>({SUPABASE_URL:'https://db.example',SUPABASE_SERVICE_ROLE_KEY:'server-only',RESEND_API_KEY:'resend-only'})[name];
const request=()=>new Request('https://worker.example',{method:'POST',headers:{Authorization:`Bearer ${token}`}});
function mockFetch(status=200){const calls=[];return {calls,run:async(url,options)=>{const body=JSON.parse(options.body);calls.push({url,options,body});return Response.json(url.endsWith('admin_alerts_claim')?[item]:url.endsWith('admin_alerts_finish')?true:{id:'provider-one'},{status:url.includes('api.resend')?status:200});}};}
test('reject unauthenticated requests without accessing database or Resend',async()=>{let calls=0;const handler=createHandler({env,fetchImpl:async()=>{calls++}});assert.equal((await handler(new Request('https://worker.example',{method:'POST'}))).status,401);assert.equal(calls,0);});
test('missing credentials only update configuration state, never send',async()=>{const m=mockFetch();const r=await createHandler({env:n=>n==='RESEND_API_KEY'?undefined:env(n),fetchImpl:m.run})(request());assert.equal(r.status,503);assert.equal(m.calls.length,1);assert.equal(m.calls[0].body.p_configured,false);});
test('send only to authorized recipient; finish after provider acceptance',async()=>{const m=mockFetch();const r=await createHandler({env,fetchImpl:m.run})(request());assert.equal(r.status,200);assert.deepEqual(m.calls[1].body.to,['salmin@saltecsolutions.co.tz']);assert.equal(m.calls[1].options.headers['Idempotency-Key'],'betslip-admin/event-one');assert.equal(m.calls[2].body.p_provider_id,'provider-one');assert.equal(m.calls[2].body.p_lease,'lease-one');});
for(const status of [429,500,401,422])test(`HTTP ${status} retry classification`,async()=>{const m=mockFetch(status);await createHandler({env,fetchImpl:m.run})(request());assert.equal(m.calls[2].body.p_retry,status===429||status===500);assert.equal(m.calls[2].body.p_provider_id,null);});
test('lost database response after sending never reports success',async()=>{const m=mockFetch();const r=await createHandler({env,fetchImpl:async(u,o)=>{if(u.endsWith('admin_alerts_finish'))throw Error('offline');return m.run(u,o);}})(request());assert.equal(r.status,503);});
test('no private event payload or arbitrary link can enter email',()=>{const text=JSON.stringify(emailFor({...item,details:'SECRET KYC',url:'https://evil.invalid',recipient:'attacker@example.com'}));assert.ok(!text.includes('SECRET KYC'));assert.ok(!text.includes('evil.invalid'));assert.ok(!text.includes('attacker@example.com'));});
test('weekly partner email is restricted to fixed aggregate fields and recipient',()=>{
 const s={period_start:'2026-08-31',period_end:'2026-09-06',new_users:2,publishing_tipsters:1,published_content:3,paid_purchases:4,partnership_requests:0,kyc:'SECRET',revenue:200000};
 const mail=emailFor({id:'weekly',kind:'partner_weekly',summary:s});
 assert.deepEqual(mail.to,['jdaking08@gmail.com']);
 assert.ok(!JSON.stringify(mail).includes('SECRET'));assert.ok(!JSON.stringify(mail).includes('200000'));
 assert.ok(!mail.text.includes('/admin'));assert.ok(mail.text.includes('2026-08-31'));
 assert.throws(()=>emailFor({kind:'partner_weekly',summary:{...s,new_users:'<script>'}}));
});
test('support customer email uses only verified server payload fields and ticket link',()=>{
 const summary={ticket_id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',number:42,email:'customer@example.com',body:'PRIVATE MESSAGE',url:'https://evil.invalid'};
 const mail=emailFor({kind:'support_customer',summary});
 assert.deepEqual(mail.to,['customer@example.com']);assert.ok(mail.text.includes('/support/'+summary.ticket_id));
 assert.ok(!JSON.stringify(mail).includes('PRIVATE MESSAGE'));assert.ok(!JSON.stringify(mail).includes('evil.invalid'));
 assert.throws(()=>emailFor({kind:'support_customer',summary:{...summary,email:'a@example.com\r\nBcc:other@example.com'}}));
 assert.throws(()=>emailFor({kind:'support_customer',summary:{...summary,ticket_id:'//evil.invalid'}}));
});
test('overdue support escalation is routed only to Salmin',()=>{
 const mail=emailFor({kind:'support_escalation',id:'overdue',summary:{email:'other@example.com'}});
 assert.deepEqual(mail.to,['salmin@saltecsolutions.co.tz']);assert.ok(mail.text.includes('/support/team'));
});
