"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

type Profile = {
  id: string;
  full_name: string | null;
  role: "bettor" | "tipster" | "advertiser" | "admin" | "super_admin";
  status: string;
};

export default function DashboardPage() {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const { data: authData } = await supabase.auth.getUser();
      if (!authData.user) {
        router.replace("/login");
        return;
      }
      const { data } = await supabase
        .from("profiles")
        .select("id,full_name,role,status")
        .eq("id", authData.user.id)
        .single();
      setProfile(data as Profile | null);
      setLoading(false);
    })();
  }, [router, supabase]);

  async function logout() {
    await supabase.auth.signOut();
    router.replace("/login");
  }

  if (loading) return <main className="container"><p>Loading...</p></main>;
  if (!profile) return <main className="container"><p>Profile not found.</p></main>;

  const links = profile.role === "tipster"
    ? [{ href: "/tipster/predictions/new", label: "Add Prediction / Ongeza Prediction" }, { href: "/tipster", label: "Tipster Dashboard" }]
    : profile.role === "advertiser"
      ? [{ href: "/advertiser", label: "Advertiser Dashboard" }, { href: "/advertise", label: "Ad Packages" }]
      : profile.role === "admin" || profile.role === "super_admin"
        ? [{ href: "/admin", label: "Admin Panel" }]
        : [{ href: "/predictions", label: "Browse Predictions / Angalia Predictions" }, { href: "/purchases", label: "My Purchases / Nilizonunua" }];

  return (
    <main className="container">
      <section className="panel">
        <div className="brand">BETSLIP <span>PRO</span></div>
        <h1>Karibu, {profile.full_name || "Member"}</h1>
        <p className="muted">Role: {profile.role} · Status: {profile.status}</p>
        <div className="actions">
          {links.map((item) => <Link className="btn btn-primary" key={item.href} href={item.href}>{item.label}</Link>)}
          <button className="btn" onClick={logout}>Logout / Toka</button>
        </div>
      </section>
    </main>
  );
}
