import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function POST(req: NextRequest) {
  const expectedSecret = process.env.BETSLIP_PRO_BOOTSTRAP_ADMIN_SECRET;
  if (!expectedSecret) return NextResponse.json({ error: "Bootstrap disabled" }, { status: 503 });

  const secret = req.headers.get("x-bootstrap-secret");
  if (!secret || Buffer.byteLength(secret) !== Buffer.byteLength(expectedSecret) || !timingSafeEqual(Buffer.from(secret), Buffer.from(expectedSecret))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Promote an existing email-confirmed account. Never accept passwords here.
  let userId: unknown;
  try { ({ userId } = await req.json()); } catch { return NextResponse.json({error:"Invalid request"},{status:400}); }
  if(typeof userId!=="string" || !/^[0-9a-f-]{36}$/i.test(userId)) return NextResponse.json({error:"Valid user ID required"},{status:400});
  const supabase = createAdminClient();
  const { error } = await supabase.rpc("bootstrap_super_admin", { p_user_id: userId });
  if(error) return NextResponse.json({error:"Bootstrap unavailable or account not confirmed"},{status:409});
  return NextResponse.json({ok:true});
}
