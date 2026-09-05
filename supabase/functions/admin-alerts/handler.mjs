const recipient = 'salmin@saltecsolutions.co.tz';
const messages = {
  partnership: ['Ombi jipya la partnership / New partnership request', '/admin/partnerships'],
  privacy: ['Ombi la faragha linahitaji hatua / Privacy request needs attention', '/admin/compliance'],
  permissions: ['Ruhusa za usimamizi zimebadilika / Admin permissions changed', '/admin/compliance'],
  dispute: ['Malalamiko mapya ya ununuzi / New purchase dispute', '/admin/compliance'],
  payment_failed: ['Malipo yamewekwa kama yameshindwa / Payment marked failed', '/admin/payments'],
  integrity: ['Ukaguzi wa uadilifu umebadilika / Integrity review updated', '/admin/trust'],
  test: ['Jaribio la notifications / Notifications test', '/admin/alerts'],
};
export function emailFor(item) {
  if(item.kind==='partner_weekly') {
    const summary=item.summary;
    const keys=['new_users','publishing_tipsters','published_content','paid_purchases','partnership_requests'];
    if(!summary || !keys.every(k=>Number.isSafeInteger(summary[k]) && summary[k]>=0) ||
      !['period_start','period_end'].every(k=>/^\d{4}-\d{2}-\d{2}$/.test(summary[k]))) throw new Error('invalid_weekly_summary');
    return {from:'Betslip Pro <noreply@betslip.co.tz>',to:['jdaking08@gmail.com'],
      subject:`Betslip Pro: Muhtasari wa wiki / Weekly update — ${summary.period_start}`,
      text:`Habari Jimmy,\n\nMuhtasari wa Betslip Pro: ${summary.period_start} hadi ${summary.period_end} (saa za Tanzania).\nWeekly activity summary, Tanzania time.\n\nWatumiaji wapya / New users: ${summary.new_users}\nTipsters waliochapisha / Tipsters who published: ${summary.publishing_tipsters}\nPrediction na Betslip zilizochapishwa / Published content: ${summary.published_content}\nManunuzi yaliyothibitishwa kulipwa / Verified paid purchases: ${summary.paid_purchases}\nMaombi mapya ya partnership / New partnership requests: ${summary.partnership_requests}\n\nHizi ni takwimu za jumla zilizorekodiwa wakati ripoti inaandaliwa. Manunuzi yaliyorejeshewa fedha kabla ya ripoti hayajahesabiwa kama mauzo.\nThese are aggregate figures recorded when the report was prepared; purchases already refunded are excluded from the sales count.\n\nKwa maelezo ya maendeleo na mipango, wasiliana na Salmin.\nFor project progress and plans, contact Salmin.\n\nhttps://www.betslip.co.tz`};
  }
  const message = messages[item.kind];
  if (!message) throw new Error('unknown_kind');
  return {from:'Betslip Pro <noreply@betslip.co.tz>',to:[recipient],subject:`Betslip Pro: ${message[0]}`,
    text:`${message[0]}\n\nIngia kwenye dashboard ukague taarifa na hatua inayohitajika.\nSign in to your dashboard to review the details and take action.\n\nhttps://www.betslip.co.tz${message[1]}\n\nTaarifa binafsi hazijawekwa kwenye email hii. Personal details are kept in the protected dashboard.\nReference: ${item.id}`};
}
export function createHandler({env,fetchImpl=fetch}) {
  async function rpc(name,args) {
    const key=env('SUPABASE_SERVICE_ROLE_KEY');
    const res=await fetchImpl(`${env('SUPABASE_URL')}/rest/v1/rpc/${name}`,{
      method:'POST',headers:{apikey:key,Authorization:`Bearer ${key}`,'Content-Type':'application/json'},
      body:JSON.stringify(args),signal:AbortSignal.timeout(8000)});
    if(!res.ok) { const detail=await res.json().catch(()=>({})); console.error('admin_alerts_rpc_failed',res.status,typeof detail.code==='string'?detail.code.slice(0,30):'unknown', String(detail.message||'').replaceAll(args.p_token||'__none__','[redacted]').slice(0,200)); throw new Error('database_request_failed'); }
    return res.json();
  }
  const response=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
  return async req=>{
    if(req.method!=='POST') return response(405,{error:'method_not_allowed'});
    const token=req.headers.get('Authorization')?.match(/^Bearer ([a-f0-9]{64})$/)?.[1];
    if(!token) return response(401,{error:'unauthorized'});
    if(!env('SUPABASE_URL')||!env('SUPABASE_SERVICE_ROLE_KEY')) return response(503,{error:'server_configuration'});
    const resendKey=env('RESEND_API_KEY');
    let items;
    try {items=await rpc('admin_alerts_claim',{p_token:token,p_configured:!!resendKey});}
    catch {return response(401,{error:'worker_not_authorized_or_unavailable'});}
    if(!resendKey) return response(503,{error:'missing_resend_key'});
    let accepted=0,failed=0;
    for(const item of items) {
      let providerId=null,errorCode=null,retry=false;
      try {
        const email=emailFor(item);
        const result=await fetchImpl('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${resendKey}`,'Content-Type':'application/json','Idempotency-Key':`betslip-admin/${item.id}`},body:JSON.stringify(email),signal:AbortSignal.timeout(8000)});
        if(result.ok) {
          const data=await result.json();
          if(typeof data.id==='string' && data.id.length<=128) providerId=data.id;
          else {errorCode='invalid_provider_response';retry=true;}
        } else {errorCode=`resend_http_${result.status}`;retry=result.status===429||result.status===409||result.status>=500;}
      } catch {errorCode='network_or_payload_error';retry=true;}
      try {
        const saved=await rpc('admin_alerts_finish',{p_id:item.id,p_lease:item.lease_token,p_provider_id:providerId,p_error:errorCode,p_retry:retry});
        if(!saved) return response(503,{error:'lease_lost'});
      } catch {return response(503,{error:'delivery_record_pending'});}
      if(providerId) accepted++;else failed++;
    }
    return response(200,{accepted,failed});
  };
}
