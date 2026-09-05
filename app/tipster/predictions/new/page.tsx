"use client";

import { FormEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function NewPredictionPage() {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setMessage("");

    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) {
      router.replace("/login");
      return;
    }

    const { data: tipster } = await supabase
      .from("tipsters")
      .select("id,verification_status")
      .eq("user_id", authData.user.id)
      .single();

    if (!tipster || tipster.verification_status !== "active") {
      setMessage("Your tipster account must be approved first / Account yako ya tipster lazima iidhinishwe kwanza.");
      setLoading(false);
      return;
    }

    const form = new FormData(e.currentTarget);
    const priceTzs = Number(form.get("price") || 0);
    if (priceTzs < 1000 || priceTzs > 5000) {
      setMessage("Price must be between TZS 1,000 and TZS 5,000.");
      setLoading(false);
      return;
    }

    const payload = {
      tipster_id: tipster.id,
      title: String(form.get("title") || ""),
      sport: String(form.get("sport") || ""),
      league: String(form.get("league") || ""),
      match_name: String(form.get("match_name") || ""),
      prediction_text: String(form.get("prediction_text") || ""),
      betslip_code: String(form.get("betslip_code") || ""),
      odds: Number(form.get("odds") || 0) || null,
      confidence_level: Number(form.get("confidence_level") || 0) || null,
      price_tzs: priceTzs,
      category: String(form.get("category") || "single"),
      match_date: String(form.get("match_date") || ""),
      status: "pending"
    };

    const { error } = await supabase.from("predictions").insert(payload);
    if (error) setMessage(error.message);
    else {
      setMessage("Prediction submitted for review / Prediction imetumwa kwa ukaguzi.");
      e.currentTarget.reset();
    }
    setLoading(false);
  }

  return (
    <main className="container">
      <div className="form panel">
        <h1>Add Prediction / Ongeza Prediction</h1>
        <form onSubmit={submit}>
          <label>Title / Kichwa</label><input name="title" required />
          <label>Sport / Mchezo</label><input name="sport" required />
          <label>League / Ligi</label><input name="league" />
          <label>Match / Mechi</label><input name="match_name" required />
          <label>Prediction / Utabiri</label><textarea name="prediction_text" required />
          <label>Betslip code</label><input name="betslip_code" required />
          <label>Odds</label><input name="odds" type="number" step="0.01" min="1" />
          <label>Confidence %</label><input name="confidence_level" type="number" min="1" max="100" />
          <label>Price TZS</label><input name="price" type="number" min="1000" max="5000" required />
          <label>Category / Aina</label>
          <select name="category"><option value="single">Single Prediction</option><option value="betslip">Betslip</option></select>
          <label>Match date / Tarehe</label><input name="match_date" type="datetime-local" required />
          <button className="btn btn-primary" disabled={loading}>{loading ? "Submitting..." : "Submit / Tuma"}</button>
          {message && <p className="notice">{message}</p>}
        </form>
      </div>
    </main>
  );
}
