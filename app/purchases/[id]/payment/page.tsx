"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function ManualPaymentPage() {
  const { id } = useParams<{id:string}>();
  const supabase = useMemo(() => createClient(), []);
  const [purchase, setPurchase] = useState<any>(null);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    (async () => {
      const { data } = await supabase.from("purchases").select("id,amount_tzs,payment_status,payment_reference,prediction_id").eq("id", id).single();
      setPurchase(data || null);
    })();
  }, [id, supabase]);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true); setMessage("");
    const form = new FormData(e.currentTarget);
    const reference = String(form.get("reference") || "").trim();
    const note = String(form.get("note") || "").trim();
    if (!reference) { setMessage("Enter transaction reference / Weka transaction reference."); setLoading(false); return; }
    const { error } = await supabase.rpc("submit_manual_payment", { p_purchase_id: id, p_reference: reference, p_note: note || null });
    if (error) setMessage(error.message);
    else {
      setPurchase((p:any) => ({...p,payment_status:"submitted",payment_reference:reference}));
      setMessage("Payment submitted for verification / Malipo yametumwa kwa uthibitisho.");
    }
    setLoading(false);
  }

  if (!purchase) return <main className="container"><div className="panel"><p>Loading...</p></div></main>;

  return (
    <main className="container">
      <div className="form panel">
        <h1>Pay / Lipa kwa Selcom</h1>
        <p>Lipa Namba: <strong>{process.env.NEXT_PUBLIC_SELCOM_LIPA_NUMBER}</strong></p>
        <p>Merchant / Mfanyabiashara: <strong>{process.env.NEXT_PUBLIC_SELCOM_MERCHANT_NAME}</strong></p>
        <p>Order / Oda: {purchase.id}</p>
        {purchase.payment_status === "paid" && <a className="btn btn-primary" href={`/predictions/${purchase.prediction_id}`}>Open prediction / Fungua utabiri</a>}
        <p>Amount / Kiasi: <strong>TZS {Number(purchase.amount_tzs).toLocaleString()}</strong></p>
        <div className="notice">
          <strong>1.</strong> Lipa kupitia Selcom Lipa Namba ya Betslip Pro.<br/>
          <strong>2.</strong> Tumia kiasi kilichoonyeshwa hapo juu.<br/>
          <strong>3.</strong> Baada ya kulipa, weka transaction reference hapa chini.<br/>
          <strong>4.</strong> Admin akithibitisha, prediction yako itafunguka.
        </div>
        {purchase.payment_status === "pending" ? (
          <form onSubmit={submit}>
            <label>Transaction reference / Kumbukumbu ya muamala</label>
            <input name="reference" required placeholder="e.g. SEL123456789" />
            <label>Note (optional) / Maelezo</label><textarea name="note" />
            <button className="btn btn-primary" disabled={loading}>{loading ? "Submitting..." : "I have paid / Nimeshalipa"}</button>
          </form>
        ) : (
          <p className="notice">Status: <strong>{purchase.payment_status}</strong>{purchase.payment_status === "submitted" ? " — waiting for admin verification / inasubiri uthibitisho" : ""}</p>
        )}
        {message && <p className="notice">{message}</p>}
      </div>
    </main>
  );
}
