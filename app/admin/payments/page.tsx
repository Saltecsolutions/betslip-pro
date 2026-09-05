"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Purchase = {
  id:string;
  amount_tzs:number;
  platform_commission_tzs:number;
  tipster_commission_tzs:number;
  payment_reference:string|null;
  payment_status:string;
  payment_submitted_at:string|null;
};

export default function AdminPaymentsPage(){
  const supabase = useMemo(() => createClient(), []);
  const [items,setItems] = useState<Purchase[]>([]);
  const [message,setMessage] = useState("");

  async function load(){
    const { data, error } = await supabase.from("purchases")
      .select("id,amount_tzs,platform_commission_tzs,tipster_commission_tzs,payment_reference,payment_status,payment_submitted_at")
      .in("payment_status",["submitted","paid"])
      .order("payment_submitted_at",{ascending:false});
    if(error) setMessage(error.message); else setItems((data||[]) as Purchase[]);
  }

  useEffect(()=>{ void load(); },[]);

  async function verify(id:string){
    setMessage("");
    const raw = window.prompt("Payment processing fee TZS / Ada ya processing (weka 0 kama haipo)","0");
    if(raw===null) return;
    const fee = Math.max(0, Number(raw)||0);
    const { error } = await supabase.rpc("admin_verify_manual_payment",{p_purchase_id:id,p_processing_fee_tzs:fee});
    if(error) setMessage(error.message); else { setMessage("Payment verified / Malipo yamethibitishwa."); await load(); }
  }

  return <main className="container">
    <section className="panel">
      <h1>Manual Payments / Malipo ya Manual</h1>
      <p className="muted">Verify Selcom Lipa Namba payments before unlocking paid content.</p>
      {message && <p className="notice">{message}</p>}
    </section>
    <div className="grid">
      {items.map(p=><article className="card" key={p.id}>
        <span className="pill">{p.payment_status}</span>
        <h3>TZS {Number(p.amount_tzs).toLocaleString()}</h3>
        <p>Reference: <strong>{p.payment_reference || "-"}</strong></p>
        <p className="muted">Platform 30%: TZS {Number(p.platform_commission_tzs).toLocaleString()} · Tipster 70%: TZS {Number(p.tipster_commission_tzs).toLocaleString()}</p>
        {p.payment_status === "submitted" && <button className="btn btn-primary" onClick={()=>verify(p.id)}>Verify payment / Thibitisha</button>}
      </article>)}
      {!items.length && <p className="muted">No submitted payments / Hakuna malipo yanayosubiri.</p>}
    </div>
  </main>;
}
