// ECPA attendance register — teacher accounts.
// Only a signed-in admin (ecpa_profiles.role = 'admin') may call this.
// Actions: create | update | delete
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });

    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "unauthorized" }, 401);
    const { data: who, error: whoErr } = await admin.auth.getUser(token);
    if (whoErr || !who?.user) return json({ error: "unauthorized" }, 401);
    const { data: me } = await admin.from("ecpa_profiles").select("role").eq("id", who.user.id).maybeSingle();
    if (me?.role !== "admin") return json({ error: "forbidden" }, 403);

    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    if (action === "create") {
      const email = String(body.email || "").trim().toLowerCase();
      const password = String(body.password || "");
      const fullName = String(body.full_name || "").trim();
      if (!fullName) return json({ error: "bad_name" }, 400);
      if (!EMAIL_RE.test(email)) return json({ error: "bad_email" }, 400);
      if (password.length < 8) return json({ error: "weak_password" }, 400);
      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { full_name: fullName },
      });
      if (error || !data?.user) {
        const taken = /already|exists|registered/i.test(error?.message || "");
        return json({ error: taken ? "email_taken" : "create_failed", message: error?.message }, 400);
      }
      const { error: pErr } = await admin.from("ecpa_profiles")
        .insert({ id: data.user.id, full_name: fullName, email, role: "teacher" });
      if (pErr) {
        await admin.auth.admin.deleteUser(data.user.id);
        return json({ error: "create_failed", message: pErr.message }, 500);
      }
      return json({ id: data.user.id });
    }

    const id = String(body.id || "");
    if (!id) return json({ error: "bad_id" }, 400);
    const { data: target } = await admin.from("ecpa_profiles").select("role").eq("id", id).maybeSingle();
    if (!target || target.role !== "teacher") return json({ error: "not_a_teacher" }, 404);

    if (action === "update") {
      const patch: Record<string, unknown> = {};
      if (body.password) {
        if (String(body.password).length < 8) return json({ error: "weak_password" }, 400);
        patch.password = String(body.password);
      }
      if (body.email) {
        const email = String(body.email).trim().toLowerCase();
        if (!EMAIL_RE.test(email)) return json({ error: "bad_email" }, 400);
        patch.email = email;
        patch.email_confirm = true;
      }
      if (Object.keys(patch).length) {
        const { error } = await admin.auth.admin.updateUserById(id, patch);
        if (error) {
          const taken = /already|exists|registered/i.test(error.message || "");
          return json({ error: taken ? "email_taken" : "update_failed", message: error.message }, 400);
        }
      }
      const prof: Record<string, unknown> = {};
      if (body.full_name) prof.full_name = String(body.full_name).trim();
      if (patch.email) prof.email = patch.email;
      if (Object.keys(prof).length) await admin.from("ecpa_profiles").update(prof).eq("id", id);
      return json({ ok: true });
    }

    if (action === "delete") {
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) return json({ error: "delete_failed", message: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: "bad_action" }, 400);
  } catch (e) {
    return json({ error: "server_error", message: String((e as Error)?.message || e) }, 500);
  }
});
