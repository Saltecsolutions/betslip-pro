import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  const expectedSecret = process.env.BETSLIP_PRO_BOOTSTRAP_ADMIN_SECRET;
  if (!expectedSecret) return NextResponse.json({ error: "Bootstrap disabled" }, { status: 503 });

  const secret = req.headers.get("x-bootstrap-secret");
  if (!secret || secret !== expectedSecret) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { email, password, fullName = "Betslip Pro Admin", phone = null } = await req.json();
  if (!email || !password || String(password).length < 12) {
    return NextResponse.json({ error: "Email and password (12+ chars) are required" }, { status: 400 });
  }

  const supabase = createAdminClient();
  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, phone, requested_role: "bettor", locale: "sw" }
  });
  if (error || !data.user) {
    return NextResponse.json({ error: error?.message || "Could not create admin" }, { status: 400 });
  }

  const { error: profileError } = await supabase.from("profiles").update({
    role: "super_admin",
    requested_role: "super_admin",
    status: "active",
    age_verified: true
  }).eq("id", data.user.id);

  if (profileError) {
    await supabase.auth.admin.deleteUser(data.user.id);
    return NextResponse.json({ error: profileError.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, userId: data.user.id, email: data.user.email });
}
