"use client";
import {FormEvent,Suspense,useMemo,useState} from 'react';
import {useSearchParams,useRouter} from 'next/navigation';
import {createClient} from '@/lib/supabase/client';
import {safeNext} from '@/lib/auth-next';
function Form(){const next=safeNext(useSearchParams().get('next'));const router=useRouter();const db=useMemo(()=>createClient(),[]);const [message,setMessage]=useState('');const [busy,setBusy]=useState(false);async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();if(new FormData(e.currentTarget).get('adult')!=='on')return;setBusy(true);const {error}=await db.rpc('confirm_adult');if(error){setMessage(error.message);setBusy(false);}else router.replace(next);}return <main className="container"><form className="form panel" onSubmit={submit}><h1>Thibitisha umri / Confirm your age</h1><p>Slips ni kwa wenye miaka 18 au zaidi. Predictions si ushindi wa uhakika.</p><label className="check-label"><input type="checkbox" name="adult" required/>Nina miaka 18+ / I am 18 or older</label><button className="btn btn-primary" disabled={busy}>Endelea / Continue</button>{message&&<p role="status">{message}</p>}<p><a href="/">Rudi / Back</a></p></form></main>}
export default function ConfirmAge(){return <Suspense fallback={<main>Loading…</main>}><Form/></Suspense>}
