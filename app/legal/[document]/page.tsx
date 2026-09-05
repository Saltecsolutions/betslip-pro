'use client';
import {useEffect,useMemo,useState} from 'react';
import {createClient} from '@/lib/supabase/client';
import {useParams} from 'next/navigation';
import Link from 'next/link';
import {policies,POLICY_VERSION} from '@/lib/policies';
import {useLanguage} from '@/components/ui';
export default function Legal(){const {document}=useParams();const db=useMemo(()=>createClient(),[]);const [operator,setOperator]=useState<any>(null);useEffect(()=>{void db.rpc('operator_contact').then(({data})=>setOperator(data))},[db]);const {t}=useLanguage();const p=policies[String(document) as keyof typeof policies];if(!p)return <main className="container"><h1>{t('Policy not found','Sera haipatikani')}</h1></main>;return <main className="container"><article className="panel legal-document"><span className="eyebrow">BETSLIP PRO · {document==='seller'?POLICY_VERSION:'2026-09-05'}</span><h1>{t(p.en,p.sw)}</h1>{p.sections.map(s=><section key={s[0]}><h2>{t(s[0],s[1])}</h2><p>{t(s[2],s[3])}</p></section>)}<section><h2>{t("Operator & contact","Mwendeshaji na mawasiliano")}</h2>{operator?.legal_name?<p>{operator.legal_name}<br/>{operator.address}<br/>{operator.privacy_contact}</p>:<p>{t("Operator contact details are pending confirmation before public launch. Signed-in users can submit privacy requests below.","Mawasiliano ya mwendeshaji yanasubiri kuthibitishwa kabla ya uzinduzi. Walioingia wanaweza kutuma maombi hapa chini.")}</p>}</section><Link href="/account/privacy">{t('Privacy controls and requests','Udhibiti wa faragha na maombi')} →</Link></article></main>}
