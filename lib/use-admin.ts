'use client';
import {useEffect,useMemo,useState} from 'react';
import {createClient} from './supabase/client';
export function useAdmin(){const db=useMemo(()=>createClient(),[]);const [ready,setReady]=useState(false);useEffect(()=>{void(async()=>{const {data:{user}}=await db.auth.getUser();if(!user){window.location.assign('/login?next=/admin');return}const {data}=await db.from('profiles').select('role,status').eq('id',user.id).single();if(!data||!['admin','super_admin'].includes(data.role)||data.status!=='active'){window.location.assign('/dashboard');return}setReady(true)})()},[db]);return {db,ready}}
