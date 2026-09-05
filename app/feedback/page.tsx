'use client';

import {useRef, useState} from 'react';
import Link from 'next/link';
import {PageHeading, useLanguage} from '@/components/ui';

const formUrl='https://docs.google.com/forms/d/e/1FAIpQLScHoTX_6tOxpfK-p9GdPOU93B1scdyoG16_X9i6rsr8J_3YWg/viewform';

export default function FeedbackPage(){
 const {t}=useLanguage();
 const [showForm,setShowForm]=useState(false);
 const [loaded,setLoaded]=useState(false);
 const formFrame=useRef<HTMLIFrameElement>(null);
 const frameLoaded=useRef(false);
 return <main className="container">
  <PageHeading eyebrow={t('YOUR VOICE','MAONI YAKO')} title={t('Help improve Betslip Pro.','Tusaidie kuboresha Betslip Pro.')} description={t('Report a problem or share an idea. Your feedback goes directly to our team.','Eleza tatizo au toa pendekezo. Maoni yako yanafika moja kwa moja kwa timu yetu.')}/>
  <section className="panel" style={{maxWidth:850,margin:'0 auto 32px'}}>
   <h2>{t('Send feedback','Tuma maoni')}</h2><p><Link className="btn btn-primary" href="/support">{t("Need a reply or help with your account? Open a ticket","Unahitaji jibu au msaada wa akaunti? Fungua ticket")}</Link></p>
   <p className="muted">{t('Describe what happened, which page you were using, and your device. Contact email is optional. Never include passwords, OTPs, identity documents or payment details.','Eleza kilichotokea, ukurasa uliokuwa unatumia na kifaa chako. Email ya mawasiliano ni hiari. Usiweke nenosiri, OTP, nyaraka za utambulisho au taarifa za malipo.')}</p>
   <p className="muted">{t('This form uses Google Forms. Opening it connects to Google; responses are stored in a private Google Sheet for our team to review and track.','Fomu hii inatumia Google Forms. Ukiifungua unaunganika na Google; majibu yanahifadhiwa kwenye Google Sheet ya faragha ili timu iyakague na kufuatilia hatua.')}{' '}<Link href="/legal/privacy">{t('Privacy policy','Sera ya faragha')}</Link></p>
   <div style={{display:'flex',flexWrap:'wrap',gap:12,margin:'20px 0'}}>
    {!showForm&&<button className="btn btn-primary" onClick={()=>setShowForm(true)}>{t('Open feedback form','Fungua fomu ya maoni')}</button>}
    <a className="btn btn-secondary" href={formUrl} target="_blank" rel="noopener noreferrer">{t('Open in a new tab','Fungua kwenye tab mpya')}</a>
   </div>
   {showForm&&<>
    {!loaded&&<p role="status" className="muted">{t('Loading form… If it does not appear, use the new-tab link above.','Fomu inafunguka… Isipoonekana, tumia link ya tab mpya hapo juu.')}</p>}
    <iframe ref={formFrame} src={`${formUrl}?embedded=true`} title={t('Betslip Pro feedback form','Fomu ya maoni ya Betslip Pro')} onLoad={()=>{setLoaded(true);if(frameLoaded.current)formFrame.current?.scrollIntoView({block:'start'});frameLoaded.current=true;}} referrerPolicy="no-referrer" style={{display:'block',width:'100%',height:1050,border:0,borderRadius:12,background:'#fff',scrollMarginTop:100}}/>
   </>}
   <p className="muted" style={{marginTop:24}}>{t('Progress is tracked internally. If you leave an email, we may contact you for more information.','Hatua zinafuatiliwa na timu ndani ya mfumo. Ukiacha email, tunaweza kuwasiliana nawe tukihitaji maelezo zaidi.')}</p>
   <p><Link href="/protection">{t('Purchase problem or refund?','Tatizo la ununuzi au refund?')}</Link>{' · '}<Link href="/account/privacy">{t('Request access, correction or deletion of personal data','Omba kupata, kusahihisha au kufuta taarifa binafsi')}</Link></p>
  </section>
 </main>;
}
