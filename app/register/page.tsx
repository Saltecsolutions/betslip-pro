"use client";

import { FormEvent, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

type Role = "bettor" | "tipster" | "advertiser";

export default function RegisterPage() {
  const searchParams = useSearchParams();
  const initialRole = (searchParams.get("role") as Role) || "bettor";
  const [role, setRole] = useState<Role>(initialRole);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const supabase = useMemo(() => createClient(), []);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setMessage("");
    const form = new FormData(e.currentTarget);
    const fullName = String(form.get("fullName") || "");
    const email = String(form.get("email") || "");
    const phone = String(form.get("phone") || "");
    const password = String(form.get("password") || "");
    const ageConfirmed = form.get("ageConfirmed") === "on";

    if (!ageConfirmed) {
      setMessage("You must confirm you are 18+ / Lazima uthibitishe una miaka 18+.");
      setLoading(false);
      return;
    }

    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName, phone, requested_role: role, locale: "sw" },
      },
    });

    setMessage(error ? error.message : "Account created. Check your email to verify your account.");
    setLoading(false);
  }

  return (
    <main className="container">
      <div className="form panel">
        <div className="brand">BETSLIP <span>PRO</span></div>
        <h1>Create account / Jisajili</h1>
        <p className="muted">Choose how you want to use Betslip Pro.</p>
        <form onSubmit={handleSubmit}>
          <label>Role / Aina ya account</label>
          <select value={role} onChange={(e) => setRole(e.target.value as Role)}>
            <option value="bettor">User / Bettor</option>
            <option value="tipster">Tipster</option>
            <option value="advertiser">Advertiser</option>
          </select>

          <label>Full name / Jina kamili</label>
          <input name="fullName" required />
          <label>Phone / Simu</label>
          <input name="phone" required placeholder="+255..." />
          <label>Email</label>
          <input type="email" name="email" required />
          <label>Password / Nenosiri</label>
          <input type="password" name="password" required minLength={8} />
          <label style={{display:"flex",gap:10,alignItems:"center"}}>
            <input style={{width:"auto"}} type="checkbox" name="ageConfirmed" />
            I confirm I am 18+ / Nathibitisha nina miaka 18+
          </label>
          <button className="btn btn-primary" type="submit" disabled={loading}>
            {loading ? "Creating..." : "Create account / Jisajili"}
          </button>
          {message && <p className="notice">{message}</p>}
        </form>
      </div>
    </main>
  );
}
