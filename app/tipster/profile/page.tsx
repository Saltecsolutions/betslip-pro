"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import {useLanguage} from "@/components/ui";
import { createClient } from "@/lib/supabase/client";

export default function TipsterProfilePage() {
  const {t}=useLanguage();
  const supabase = useMemo(() => createClient(), []);
  const [tipster, setTipster] = useState<any>(null);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: authData } = await supabase.auth.getUser();
      if (!authData.user) {window.location.assign("/login?next=/tipster/profile");return;}
      const { data } = await supabase.from("tipsters").select("*").eq("user_id", authData.user.id).single();
      setTipster(data || null);
    })();
  }, [supabase]);

  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setLoading(true);
    setMessage("");
    const { data: authData } = await supabase.auth.getUser();
    if (!authData.user) { setLoading(false); return; }

    const form = new FormData(e.currentTarget);
    const file = form.get("photo") as File;
    let profileImageUrl = tipster?.profile_image_url || null;

    if (file && file.size > 0) {
      if (!["image/jpeg","image/png","image/webp"].includes(file.type)) {
        setMessage(t('Upload a JPG, PNG or WebP image.','Pakia picha ya JPG, PNG au WebP.'));
        setLoading(false); return;
      }
      if (file.size > 5 * 1024 * 1024) {
        setMessage(t('Image must be under 5MB.','Picha iwe chini ya 5MB.'));
        setLoading(false); return;
      }
      const ext = file.name.split(".").pop() || "jpg";
      const path = `${authData.user.id}/profile.${ext}`;
      const { error: uploadError } = await supabase.storage.from("tipster-profiles").upload(path, file, { upsert: true });
      if (uploadError) { setMessage(uploadError.message); setLoading(false); return; }
      profileImageUrl = supabase.storage.from("tipster-profiles").getPublicUrl(path).data.publicUrl;
    }

    const payload = {
      display_name: String(form.get("display_name") || ""),
      bio: String(form.get("bio") || ""),
      location: String(form.get("location") || ""),
      sports_specialty: String(form.get("sports_specialty") || "").split(",").map(v => v.trim()).filter(Boolean),
      profile_image_url: profileImageUrl
    };

    const { data, error } = await supabase.from("tipsters").update(payload).eq("user_id", authData.user.id).select().single();
    if (error) setMessage(error.message);
    else { setTipster(data); setMessage(t('Profile updated.','Wasifu umesasishwa.')); }
    setLoading(false);
  }

  if (!tipster) return <main className="container"><div className="panel"><p>{t('Tipster profile not found.','Wasifu wa tipster haujapatikana.')}</p></div></main>;

  return (
    <main className="container">
      <div className="form panel">
        <h1>{t('Your expert profile','Wasifu wako wa mtaalamu')}</h1>
        <p className="muted">{t('Let buyers get to know the person behind the predictions.','Wape wanunuzi nafasi ya kumjua mtaalamu wa utabiri.')}</p>
        {tipster.profile_image_url && <img src={tipster.profile_image_url} alt="Tipster profile" style={{width:120,height:120,borderRadius:"50%",objectFit:"cover"}} />}
        <form onSubmit={save}>
          <label htmlFor="photo">{t('Profile photo','Picha ya wasifu')}</label><input type="file" id="photo" name="photo" accept="image/jpeg,image/png,image/webp" />
          <label htmlFor="display_name">{t('Display name','Jina la kuonekana')}</label><input id="display_name" name="display_name" defaultValue={tipster.display_name || ""} required />
          <label htmlFor="location">{t('Location','Eneo')}</label><input id="location" name="location" defaultValue={tipster.location || ""} placeholder="Dar es Salaam" />
          <label htmlFor="sports_specialty">{t('Sports specialties','Michezo unayobobea')}</label><input id="sports_specialty" name="sports_specialty" defaultValue={(tipster.sports_specialty || []).join(", ")} placeholder="Football, Basketball" />
          <label htmlFor="bio">{t('About you','Kuhusu wewe')}</label><textarea id="bio" name="bio" defaultValue={tipster.bio || ""} rows={5} />
          <button className="btn btn-primary" disabled={loading}>{loading ? t('Saving…','Inahifadhi…') : t('Save profile','Hifadhi wasifu')}</button>
          {message && <p className="notice">{message}</p>}
        </form>
      </div>
    </main>
  );
}
