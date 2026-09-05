"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Tipster = {
  id: string;
  display_name: string;
  verification_status: "pending" | "active" | "suspended" | "rejected";
};

type Prediction = {
  id: string;
  title: string;
  match_name: string;
  status: string;
};

export default function AdminPage() {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [tipsters, setTipsters] = useState<Tipster[]>([]);
  const [predictions, setPredictions] = useState<Prediction[]>([]);
  const [message, setMessage] = useState("");

  async function load() {
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) return router.replace("/login");

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", authData.user.id)
      .single();

    if (!profile || !["admin", "super_admin"].includes(profile.role)) {
      router.replace("/dashboard");
      return;
    }

    const [{ data: t }, { data: p }] = await Promise.all([
      supabase.from("tipsters").select("id,display_name,verification_status").order("created_at", { ascending: false }),
      supabase.from("predictions").select("id,title,match_name,status").eq("status", "pending").order("created_at", { ascending: false })
    ]);
    setTipsters((t || []) as Tipster[]);
    setPredictions((p || []) as Prediction[]);
  }

  useEffect(() => { void load(); }, []);

  async function setTipsterStatus(id: string, status: Tipster["verification_status"]) {
    const { error } = await supabase.rpc("admin_set_tipster_status", { p_tipster_id: id, p_status: status });
    setMessage(error ? error.message : `Tipster status changed to ${status}.`);
    if (!error) await load();
  }

  async function moderatePrediction(id: string, status: "published" | "rejected") {
    const { error } = await supabase
      .from("predictions")
      .update({ status, published_at: status === "published" ? new Date().toISOString() : null })
      .eq("id", id);
    setMessage(error ? error.message : `Prediction ${status}.`);
    if (!error) await load();
  }

  return (
    <main className="container">
      <section className="panel">
        <div className="brand">BETSLIP <span>PRO</span></div>
        <h1>Admin Panel</h1>
        <p className="muted">Manage tipster verification and prediction moderation.</p>
        {message && <p className="notice">{message}</p>}
      </section>

      <section className="panel">
        <h2>Tipsters</h2>
        <div className="grid">
          {tipsters.map((t) => (
            <div className="card" key={t.id}>
              <strong>{t.display_name}</strong>
              <p>Status: {t.verification_status}</p>
              <div className="actions">
                <button className="btn btn-primary" onClick={() => setTipsterStatus(t.id, "active")}>Approve</button>
                <button className="btn" onClick={() => setTipsterStatus(t.id, "rejected")}>Reject</button>
                <button className="btn" onClick={() => setTipsterStatus(t.id, "suspended")}>Suspend</button>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="panel">
        <h2>Pending Predictions</h2>
        <div className="grid">
          {predictions.map((p) => (
            <div className="card" key={p.id}>
              <strong>{p.title}</strong>
              <p>{p.match_name}</p>
              <div className="actions">
                <button className="btn btn-primary" onClick={() => moderatePrediction(p.id, "published")}>Publish</button>
                <button className="btn" onClick={() => moderatePrediction(p.id, "rejected")}>Reject</button>
              </div>
            </div>
          ))}
        </div>
      </section>
    </main>
  );
}
