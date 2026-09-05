"use client";

import { useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Prediction = {
  id: string;
  title: string;
  sport: string;
  league: string | null;
  match_name: string;
  odds: number | null;
  confidence_level: number | null;
  price_tzs: number;
  match_date: string;
};

export default function PredictionsPage() {
  const supabase = useMemo(() => createClient(), []);
  const [items, setItems] = useState<Prediction[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from("predictions")
        .select("id,title,sport,league,match_name,odds,confidence_level,price_tzs,match_date")
        .eq("status", "published")
        .order("match_date", { ascending: true });
      setItems((data || []) as Prediction[]);
      setLoading(false);
    })();
  }, [supabase]);

  return (
    <main className="container">
      <section className="panel">
        <div className="brand">BETSLIP <span>PRO</span></div>
        <h1>Predictions / Utabiri</h1>
        <p className="muted">Predictions are not guaranteed wins. Bet responsibly. / Prediction si ushindi wa uhakika. Cheza kwa uwajibikaji.</p>
      </section>
      {loading ? <p>Loading...</p> : (
        <div className="grid">
          {items.map((p) => (
            <article className="card" key={p.id}>
              <span className="pill">{p.sport}</span>
              <h2>{p.title}</h2>
              <p>{p.match_name}</p>
              <p className="muted">{p.league || ""}</p>
              <p>Odds: {p.odds ?? "-"} · Confidence: {p.confidence_level ?? "-"}%</p>
              <strong>TZS {Number(p.price_tzs).toLocaleString()}</strong>
              <a className="btn btn-primary" href={`/predictions/${p.id}`}>View / Angalia</a>
            </article>
          ))}
          {!items.length && <p className="muted">No published predictions yet / Hakuna predictions zilizochapishwa bado.</p>}
        </div>
      )}
    </main>
  );
}
