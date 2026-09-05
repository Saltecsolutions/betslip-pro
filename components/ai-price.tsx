'use client';
import {useEffect,useMemo,useState} from 'react';
import {createClient} from '@/lib/supabase/client';
import {Money,useLanguage} from '@/components/ui';
export function AiPrice(){
 const db=useMemo(()=>createClient(),[]);const {t}=useLanguage();const [price,setPrice]=useState<any>(null);const [error,setError]=useState(false);
 useEffect(()=>{void db.rpc('my_ai_price').then(({data,error})=>{setPrice(data);setError(!!error);});},[db]);
 return <section className="panel" aria-label={t('AI pricing','Bei ya AI')}><span className="eyebrow">{t('PRICE SET BY BETSLIP PRO AI','BEI IMEPANGWA NA BETSLIP PRO AI')}</span><h2>{price?<Money amount={price.price_tzs}/>:error?t('Price unavailable','Bei haipatikani'):'…'}</h2><p>{price?t(price.reason_en,price.reason_sw):t('Your price will be confirmed by the system on publication.','Bei yako itathibitishwa na mfumo unapochapisha.')}</p>{price&&<p className="compact-copy">{t(`Next review requires ${price.results_remaining} more verified results and at least 24 hours since the last review.`,`Ukaguzi ujao unahitaji matokeo mengine ${price.results_remaining} yaliyothibitishwa na angalau saa 24 tangu ukaguzi uliopita.`)}</p>}<small>{t('Applies to new publications. Published prices stay fixed.','Inatumika kwa machapisho mapya. Bei zilizochapishwa hazibadiliki.')}</small></section>;
}
