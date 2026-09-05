'use client';
import Link from 'next/link';import {policies} from '@/lib/policies';import {useLanguage} from '@/components/ui';
export default function Legal(){const {t}=useLanguage();return <main className="container"><h1>{t('Trust & policies','Uaminifu na sera')}</h1><div className="grid">{Object.entries(policies).map(([key,p])=><Link className="card" key={key} href={'/legal/'+key}><h2>{t(p.en,p.sw)} ↗</h2></Link>)}</div></main>}
