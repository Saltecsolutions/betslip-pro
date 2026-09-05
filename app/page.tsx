"use client";

import Link from "next/link";
import { useState } from "react";
import { Locale, messages } from "@/lib/i18n";

export default function HomePage() {
  const [locale, setLocale] = useState<Locale>("sw");
  const t = messages[locale];

  return (
    <main className="container">
      <nav className="nav">
        <div className="brand">BETSLIP <span>PRO</span></div>
        <div className="lang">
          <button className={locale === "sw" ? "active" : ""} onClick={() => setLocale("sw")}>SW</button>
          <button className={locale === "en" ? "active" : ""} onClick={() => setLocale("en")}>EN</button>
        </div>
      </nav>

      <section className="hero">
        <div>
          <span className="badge">18+ • Sports Prediction Marketplace</span>
          <h1>{t.hero}</h1>
          <p>{t.tagline}</p>
          <div className="actions">
            <Link className="btn btn-primary" href="/register">{t.getStarted}</Link>
            <Link className="btn btn-secondary" href="/register?role=tipster">{t.becomeTipster}</Link>
            <Link className="btn btn-secondary" href="/advertise">{t.advertise}</Link>
          </div>
          <p className="notice">{t.disclaimer}</p>
        </div>
        <div className="panel">
          <span className="badge">{t.verified}</span>
          <h2>Pro Analyst TZ</h2>
          <p className="muted">30-Day ROI +18% • Win Rate 64% • Avg Odds 1.92</p>
          <div className="grid">
            <div className="card"><strong>147</strong><div className="muted">Verified Picks</div></div>
            <div className="card"><strong>86/100</strong><div className="muted">Betslip Pro Score</div></div>
            <div className="card"><strong>3,820</strong><div className="muted">Followers</div></div>
          </div>
        </div>
      </section>
    </main>
  );
}
