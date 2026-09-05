import {createServerClient, type CookieOptions} from '@supabase/ssr';
import {safeNext} from '@/lib/auth-next';
import {NextRequest,NextResponse} from 'next/server';
export async function GET(request:NextRequest){
 const origin=process.env.NEXT_PUBLIC_APP_URL||request.nextUrl.origin;
 const next=safeNext(request.nextUrl.searchParams.get('next'));
 const code=request.nextUrl.searchParams.get('code');
 if(!code)return NextResponse.redirect(new URL(`/login?verification=failed&next=${encodeURIComponent(next)}`,origin));
 const response=NextResponse.redirect(new URL(next,origin));
 const db=createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{cookies:{getAll:()=>request.cookies.getAll(),setAll:(items:{name:string;value:string;options:CookieOptions}[])=>items.forEach(({name,value,options})=>response.cookies.set(name,value,options))}});
 const {error}=await db.auth.exchangeCodeForSession(code);
 if(!error){const {data:status,error:policyError}=await db.rpc("policy_status");if(policyError||!status?.accepted)response.headers.set("Location",new URL("/account/privacy?next="+encodeURIComponent(next),origin).toString());}
 response.headers.set("Cache-Control","private, no-store");
 return error?NextResponse.redirect(new URL(`/login?verification=failed&next=${encodeURIComponent(next)}`,origin)):response;
}
