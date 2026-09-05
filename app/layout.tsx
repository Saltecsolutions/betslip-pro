import type {Metadata} from 'next';
import './globals.css';
import {AppShell} from '@/components/ui';
export const metadata:Metadata={title:{default:'Betslip Pro — Find. Verify. Follow. Buy.',template:'%s | Betslip Pro'},description:'The sports prediction marketplace. Discover verified experts, compare transparent performance and follow your favourites.'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body><AppShell>{children}</AppShell></body></html>}
