import {Suspense} from 'react';
import AuthForm from '@/components/auth-form';
export default function Register(){return <Suspense fallback={<main>Inapakia / Loading…</main>}><AuthForm initialMode="signup"/></Suspense>}
