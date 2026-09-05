import {NextResponse} from 'next/server';
export async function GET(){try{
 const response=await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/settings`,{headers:{apikey:process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!},next:{revalidate:60},signal:AbortSignal.timeout(5000)});
 if(!response.ok)throw new Error('Unavailable');const settings=await response.json();
 return NextResponse.json({google:settings.external?.google===true,apple:settings.external?.apple===true});
}catch{return NextResponse.json({google:false,apple:false});}}
