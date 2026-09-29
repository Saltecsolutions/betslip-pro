'use client';
import {FormEvent,useEffect,useMemo,useState} from 'react';
import Link from 'next/link';
import {createClient} from '@/lib/supabase/client';
import {useLanguage} from './ui';

export default function PasswordRecovery({reset=false}:{reset?:boolean}) {
 const db=useMemo(()=>createClient(),[]);
 const {t}=useLanguage();
 const [busy,setBusy]=useState(false);
 const [ready,setReady]=useState(!reset);
 const [sent,setSent]=useState(false);
 const [message,setMessage]=useState('');
 useEffect(()=>{
  if(reset){void db.auth.getUser().then(({data,error})=>{
   if(error||!data.user)window.location.replace('/forgot-password?error=expired');
   else setReady(true);
  }).catch(()=>window.location.replace('/forgot-password?error=expired'));}
  else if(new URLSearchParams(window.location.search).get('error')) setMessage(t('This link is invalid or expired. Request a new link and open it in this browser.','Kiungo si halali au kimeisha muda. Omba kipya na ukifungue kwenye browser hii.'));
 },[db,reset]);
 async function submit(event:FormEvent<HTMLFormElement>){
  event.preventDefault();if(busy)return;
  const form=new FormData(event.currentTarget);
  setMessage('');
  if(reset&&form.get('password')!==form.get('confirm')){setMessage(t('Passwords do not match.','Nenosiri halifanani.'));return;}
  setBusy(true);
  try {
   if(reset){
    const {error}=await db.auth.updateUser({password:String(form.get('password'))});
    if(error){
     setMessage(error.code==='same_password'?t('Choose a different password.','Chagua nenosiri tofauti.'):error.code==='weak_password'?t('Choose a stronger password with at least 8 characters.','Chagua nenosiri imara lenye angalau herufi 8.'):t('Password could not be changed. Try again or request a new link.','Nenosiri halijabadilishwa. Jaribu tena au omba kiungo kipya.'));
     return;
    }
    // End this recovery session before asking the account owner to sign in again.
    await db.auth.signOut({scope:'local'});
    window.location.replace('/login?password=updated');
   } else {
    const {error}=await db.auth.resetPasswordForEmail(String(form.get('email')).trim(),{redirectTo:window.location.origin+'/auth/callback?next=%2Faccount%2Freset-password'});
    if(error){setMessage(t('We could not process the request. Wait a moment and try again.','Ombi halijakamilika. Subiri kidogo kisha jaribu tena.'));return;}
    setSent(true);
   }
  } catch {setMessage(t('Connection failed. Please try again.','Muunganisho umeshindikana. Jaribu tena.'));}
  finally {setBusy(false);}
 }
 return <main className="container auth-layout auth-signup"><section className="form panel">
  <h1>{reset?t('Set a new password','Weka nenosiri jipya'):t('Forgot password?','Umesahau nenosiri?')}</h1>
  {message&&<p className="notice" role="alert">{message}</p>}
  {!ready?<p role="status">{t('Checking your link…','Tunahakiki kiungo…')}</p>:sent?<p className="notice" role="status">{t('If an account exists for this email, you will receive a reset link. Check your inbox and spam folder. Open the link in this browser.','Kama email hii ina akaunti, utapokea kiungo cha kubadili nenosiri. Angalia inbox na spam. Fungua kiungo kwenye browser hii.')}</p>:<form onSubmit={submit}>
   {reset?<><label>{t('New password','Nenosiri jipya')}<input name="password" type="password" autoComplete="new-password" required minLength={8}/><small className="muted">{t('At least 8 characters','Angalau herufi 8')}</small></label><label>{t('Confirm new password','Rudia nenosiri jipya')}<input name="confirm" type="password" autoComplete="new-password" required minLength={8}/></label></>:<><p className="compact-copy">{t('Enter your account email to receive a reset link.','Weka email ya akaunti yako upokee kiungo cha kubadili nenosiri.')}</p><label>Email<input name="email" type="email" autoComplete="email" required/></label></>}
   <button className="btn btn-primary auth-submit" disabled={busy}>{busy?t('Please wait…','Subiri…'):reset?t('Save password','Hifadhi nenosiri'):t('Send reset link','Tuma kiungo')}</button>
  </form>}
  <p className="auth-switch"><Link href="/login">{t('Back to sign in','Rudi kuingia')}</Link>{reset&&<> · <Link href="/forgot-password">{t('Request a new link','Omba kiungo kipya')}</Link></>}</p>
 </section></main>;
}
