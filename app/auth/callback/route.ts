import {createServerClient, type CookieOptions} from '@supabase/ssr';
import {NextRequest,NextResponse} from 'next/server';
export async function GET(request:NextRequest){
 const origin=process.env.NEXT_PUBLIC_APP_URL||request.nextUrl.origin;
 const code=request.nextUrl.searchParams.get('code');
 if(!code)return NextResponse.redirect(new URL('/login',origin));
 const response=NextResponse.redirect(new URL('/dashboard',origin));
 const db=createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{cookies:{getAll:()=>request.cookies.getAll(),setAll:(items:{name:string;value:string;options:CookieOptions}[])=>items.forEach(({name,value,options})=>response.cookies.set(name,value,options))}});
 const {error}=await db.auth.exchangeCodeForSession(code);
 return error?NextResponse.redirect(new URL('/login?verification=failed',origin)):response;
}
