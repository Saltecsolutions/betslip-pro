"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Prediction = {
  id: string;
  tipster_id: string;
  title: string;
  sport: string;
  league: string | null;
  match_name: string;
  odds: number | null;
  confidence_level: number | null;
  price_tzs: number;
  match_date: string;
};

export default function PredictionDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [prediction, setPrediction] = useState<Prediction | null>(null);
  const [protectedContent, setProtectedContent] = useState<{prediction_text:string; betslip_code:string} | null>(null);
  const autoBuy=useRef(false);
  const [loaded,setLoaded]=useState(false);
  const [busy,setBusy]=useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from("predictions")
        .select("id,tipster_id,title,sport,league,match_name,odds,confidence_level,price_tzs,match_date")
        .eq("id", params.id)
        .single();
      setPrediction(data as Prediction | null);
      setLoaded(true);

      const { data: unlocked } = await supabase.rpc("get_prediction_protected_content", { p_prediction_id: params.id });
      if (Array.isArray(unlocked) && unlocked[0]) setProtectedContent(unlocked[0]);
    })();
  }, [params.id, supabase]);

  useEffect(()=>{if(prediction && !autoBuy.current && new URLSearchParams(window.location.search).get("buy")==="1"){autoBuy.current=true;void createPurchase();}},[prediction]);

  async function createPurchase() {
    if(busy)return;
    setBusy(true);
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) {
      router.push(`/login?next=${encodeURIComponent(`/predictions/${params.id}?buy=1`)}`);
      return;
    }
    if (!prediction) {setBusy(false);return;}
    const {data:profile}=await supabase.from("profiles").select("age_verified").eq("id",authData.user.id).single();
    if(!profile?.age_verified){router.push(`/account/confirm-age?next=${encodeURIComponent(`/predictions/${params.id}?buy=1`)}`);return;}

    const { data: purchaseId, error } = await supabase.rpc("create_purchase", { p_prediction_id: prediction.id });
    if (error) {setMessage(error.message);setBusy(false);}
    else router.push(`/purchases/${purchaseId}/payment`);
  }

  if (!prediction) return <main className="container"><p>{loaded?"Slip haipatikani / Slip unavailable":"Loading / Inapakia…"}</p><a href="/">← Angalia slips / Browse slips</a></main>;

  return (
    <main className="container">
      <section className="panel">
        <span className="pill">{prediction.sport}</span>
        <h1>{prediction.title}</h1>
        <p>{prediction.match_name}</p>
        <p className="muted">{prediction.league || ""}</p>
        <p>Odds: {prediction.odds ?? "-"} · Confidence: {prediction.confidence_level ?? "-"}%</p>
        <h2>TZS {Number(prediction.price_tzs).toLocaleString()}</h2>
        <p className="muted">Predictions are not guaranteed wins. Bet responsibly. / Prediction si ushindi wa uhakika. Cheza kwa uwajibikaji.</p>

        {protectedContent ? (
          <div className="card">
            <h3>Unlocked / Imefunguliwa</h3>
            <p>{protectedContent.prediction_text}</p>
            <strong>Betslip code: {protectedContent.betslip_code}</strong>
          </div>
        ) : (
          <button className="btn btn-primary" disabled={busy} onClick={createPurchase}>{busy?"Subiri / Please wait…":"Buy / Nunua"}</button>
        )}
        {message && <p className="notice">{message}</p>}
      </section>
    </main>
  );
}
