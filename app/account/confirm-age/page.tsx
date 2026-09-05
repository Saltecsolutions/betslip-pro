"use client";
import {FormEvent,Suspense,useMemo,useState} from 'react';
import {useSearchParams,useRouter} from 'next/navigation';
import {createClient} from '@/lib/supabase/client';
import {useLanguage} from '@/components/ui';
import {safeNext} from '@/lib/auth-next';
function Form(){const {t}=useLanguage();const next=safeNext(useSearchParams().get('next'));const router=useRouter();const db=useMemo(()=>createClient(),[]);const [message,setMessage]=useState('');const [busy,setBusy]=useState(false);async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();if(new FormData(e.currentTarget).get('adult')!=='on')return;setBusy(true);const {error}=await db.rpc('confirm_adult');if(error){setMessage(error.message);setBusy(false);}else router.replace(next);}return <main className="container"><form className="form panel" onSubmit={submit}><h1>{t('Confirm your age','Thibitisha umri wako')}</h1><p>{t('Predictions are for adults 18+. There are no guaranteed wins.','Utabiri ni kwa wenye miaka 18 au zaidi. Hakuna uhakika wa ushindi.')}</p><label className="check-label"><input type="checkbox" name="adult" required/>{t('I am 18 or older','Nina miaka 18 au zaidi')}</label><button className="btn btn-primary" disabled={busy}>{t('Continue','Endelea')}</button>{message&&<p role="status">{message}</p>}<p><a href="/">{t('Back','Rudi')}</a></p></form></main>}
export default function ConfirmAge(){return <Suspense fallback={<main>Loading…</main>}><Form/></Suspense>}
