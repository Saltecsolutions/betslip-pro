'use client';
import Experts from '@/components/experts';
import {PageHeading,useLanguage} from '@/components/ui';
export default function Tipsters(){const {t}=useLanguage();return <main className="container"><PageHeading eyebrow={t('PEOPLE BEHIND THE PICKS','WATAALAMU WA UTABIRI')} title={t('Expertise. With receipts.','Utaalamu. Pamoja na ushahidi.')} description={t('Find verified sports prediction experts. Compare the complete record, then follow your favourites for free.','Tafuta wataalamu waliohakikiwa. Linganisha rekodi kamili, kisha fuata unaowapenda bila malipo.')}/><Experts/></main>}
