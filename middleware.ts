import {createServerClient,type CookieOptions} from '@supabase/ssr';
import {NextRequest,NextResponse} from 'next/server';
export async function middleware(request:NextRequest){
 let response=NextResponse.next({request});
 const db=createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{cookies:{getAll:()=>request.cookies.getAll(),setAll:(items:{name:string;value:string;options:CookieOptions}[])=>{items.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request});items.forEach(({name,value,options})=>response.cookies.set(name,value,options))}}});
 const {data:{user}}=await db.auth.getUser();
 const path=request.nextUrl.pathname;
 const protectedPath=['/revenue','/review','/support','/dashboard','/purchases','/tipster/','/admin','/account','/notifications'].some(p=>path.startsWith(p))||path==='/tipster';
 let target:string|null=null;
 if(protectedPath&&!user)target='/login?next='+encodeURIComponent(path+request.nextUrl.search);
 if(user&&protectedPath&&path!=='/account/privacy'&&!path.startsWith('/support')){
 const {data,error}=await db.rpc('policy_status');
 if(error||!data?.accepted||(path.startsWith('/tipster')&&!data?.seller))target='/account/privacy';
 }
 if(target){const redirect=NextResponse.redirect(new URL(target,request.url));response.cookies.getAll().forEach(c=>redirect.cookies.set(c));return redirect;}
 response.headers.set('Cache-Control','private, no-store');return response;
}
export const config={matcher:['/revenue/:path*','/review/:path*','/support/:path*','/dashboard/:path*','/purchases/:path*','/tipster/:path*','/admin/:path*','/account/:path*','/notifications/:path*']};
