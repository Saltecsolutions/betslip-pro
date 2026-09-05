"use client";

import { useEffect, useMemo, useState } from "react";
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
  const [message, setMessage] = useState("");

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from("predictions")
        .select("id,tipster_id,title,sport,league,match_name,odds,confidence_level,price_tzs,match_date")
        .eq("id", params.id)
        .single();
      setPrediction(data as Prediction | null);

      const { data: unlocked } = await supabase.rpc("get_prediction_protected_content", { p_prediction_id: params.id });
      if (Array.isArray(unlocked) && unlocked[0]) setProtectedContent(unlocked[0]);
    })();
  }, [params.id, supabase]);

  async function createPurchase() {
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) {
      router.push(`/login?next=/predictions/${params.id}`);
      return;
    }
    if (!prediction) return;

    const { data: purchaseId, error } = await supabase.rpc("create_purchase", { p_prediction_id: prediction.id });
    if (error) setMessage(error.message);
    else router.push(`/purchases/${purchaseId}/payment`);
  }

  if (!prediction) return <main className="container"><p>Loading...</p></main>;

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
          <button className="btn btn-primary" onClick={createPurchase}>Buy / Nunua</button>
        )}
        {message && <p className="notice">{message}</p>}
      </section>
    </main>
  );
}
