import Link from "next/link";

const packages = [
  {name:"Starter", desc:"Sponsored listing + selected banner placements"},
  {name:"Growth", desc:"Homepage + category placements + campaign reporting"},
  {name:"Premium", desc:"High-visibility takeover, leaderboard/category sponsorships, and premium reporting"},
];

export default function AdvertisePage(){
  return (
    <main className="container">
      <nav className="nav"><div className="brand">BETSLIP <span>PRO</span></div><Link href="/register?role=advertiser" className="btn btn-primary">Create Advertiser Account</Link></nav>
      <section style={{padding:"54px 0 28px"}}>
        <span className="badge">Advertise on Betslip Pro</span>
        <h1 style={{fontSize:48,maxWidth:850}}>Reach an active sports prediction audience without affecting organic performance rankings.</h1>
        <p className="muted" style={{fontSize:18,maxWidth:780}}>Run clearly labelled sponsored campaigns across homepage, tipster discovery, predictions, league/category pages, leaderboards and selected dashboard inventory.</p>
      </section>
      <section className="grid">
        {packages.map((p)=><article className="card" key={p.name}><h2>{p.name}</h2><p className="muted">{p.desc}</p><Link href="/register?role=advertiser" className="btn btn-secondary">Start campaign</Link></article>)}
      </section>
      <section className="panel" style={{marginTop:18}}>
        <h2>Campaign analytics</h2>
        <p className="muted">Advertisers will see impressions, clicks, CTR, spend, dates, placement and campaign status. Sponsored placements remain visibly labelled and never modify a tipster's verified ROI, win rate or Betslip Pro Score.</p>
      </section>
    </main>
  )
}
