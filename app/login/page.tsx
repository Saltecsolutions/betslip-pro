"use client";

import { FormEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setMessage("");
    const form = new FormData(e.currentTarget);
    const email = String(form.get("email") || "");
    const password = String(form.get("password") || "");

    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) {
      setMessage(error.message);
      setLoading(false);
      return;
    }
    router.push("/dashboard");
    router.refresh();
  }

  return (
    <main className="container">
      <div className="form panel">
        <div className="brand">BETSLIP <span>PRO</span></div>
        <h1>Login / Ingia</h1>
        <form onSubmit={handleSubmit}>
          <label>Email</label>
          <input type="email" name="email" required />
          <label>Password / Nenosiri</label>
          <input type="password" name="password" required />
          <button className="btn btn-primary" disabled={loading}>
            {loading ? "Signing in..." : "Login / Ingia"}
          </button>
          {message && <p className="notice">{message}</p>}
        </form>
        <p className="muted">No account? / Huna account? <Link href="/register">Register</Link></p>
      </div>
    </main>
  );
}
