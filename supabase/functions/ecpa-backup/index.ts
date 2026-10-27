// ECPA attendance register — daily backup to Telegram.
// Callers: the nightly pg_cron job (header x-ecpa-key = ecpa_backup_config.cron_key) or a signed-in admin.
// Actions: status | link | run | dry (builds the files without sending, returns their sizes)
// The bot token comes from the Edge Function secret TELEGRAM_BOT_TOKEN or, failing that, from Supabase Vault
// (secret ecpa_telegram_bot_token, read through public.ecpa_backup_token()). The chat is linked once with action "link"
// after the admin presses Start in their bot.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.45.4";
import * as XLSX from "npm:xlsx@0.18.5";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ecpa-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const TABLES: [string, string[]][] = [
  ["ecpa_settings", ["id"]],
  ["ecpa_profiles", ["id"]],
  ["ecpa_subjects", ["id"]],
  ["ecpa_students", ["id"]],
  ["ecpa_assignments", ["subject_id", "section", "teacher_id"]],
  ["ecpa_sessions", ["date", "subject_id", "section", "year"]],
];
const MARK: Record<string, string> = { p: "ئامادە", a: "غائب", l: "دواکەوتوو", e: "مۆڵەت" };
const STAGE: Record<number, string> = { 1: "یەکەم", 2: "دووەم", 3: "سێیەم", 4: "چوارەم" };
const stageName = (n: number) => STAGE[n] || "دەرچوو";
const uname = (e: string) => String(e || "").replace(/@ecpa\.local$/i, "");
type Row = Record<string, any>;

async function fetchAll(db: SupabaseClient, table: string, order: string[]): Promise<Row[]> {
  const out: Row[] = [];
  for (let from = 0; ; from += 1000) {
    let q = db.from(table).select("*");
    for (const c of order) q = q.order(c);
    const { data, error } = await q.range(from, from + 999);
    if (error) throw new Error(table + ": " + error.message);
    out.push(...(data || []));
    if (!data || data.length < 1000) break;
  }
  return out;
}

function workbook(d: Record<string, Row[]>) {
  const subj = new Map(d.ecpa_subjects.map((s) => [s.id, s]));
  const stu = new Map(d.ecpa_students.map((s) => [s.id, s]));
  const prof = new Map(d.ecpa_profiles.map((p) => [p.id, p]));
  const pname = (id: string) => { const p = prof.get(id); return p ? (p.full_name || uname(p.email)) : ""; };
  const teachersOf = (sid: string) =>
    [...new Set(d.ecpa_assignments.filter((a) => a.subject_id === sid).map((a) => pname(a.teacher_id)))].join("، ");
  const byKu = (a: string, b: string) => String(a || "").localeCompare(String(b || ""), "ckb");

  const students = [...d.ecpa_students].sort((a, b) => a.stage - b.stage || byKu(a.section, b.section) || byKu(a.name, b.name))
    .map((s) => ({ "قۆناغ": stageName(s.stage), "شوعبە": s.section, "ناو": s.name, "کۆد": s.code || "" }));
  const subjects = [...d.ecpa_subjects].sort((a, b) => a.stage - b.stage || (a.sort || 0) - (b.sort || 0))
    .map((s) => ({ "قۆناغ": stageName(s.stage), "وانە": s.name, "کۆی وانەکان": s.total, "مامۆستا": teachersOf(s.id) }));
  const teachers = d.ecpa_profiles.filter((p) => p.role !== "admin").sort((a, b) => byKu(a.full_name, b.full_name))
    .map((p) => ({
      "ناو": p.full_name || "", "ناوی بەکارهێنەر": uname(p.email), "ڕۆڵ": p.role === "head" ? "سەرۆکی بەش" : "مامۆستا",
      "وانەکان": d.ecpa_assignments.filter((a) => a.teacher_id === p.id).map((a) => subj.get(a.subject_id)?.name || "").filter(Boolean).join("، "),
    }));

  const sessions = [...d.ecpa_sessions].sort((a, b) => byKu(b.date, a.date));
  const attendance: Row[] = [];
  const tally = new Map<string, Row>();
  for (const s of sessions) {
    const sb = subj.get(s.subject_id);
    const marks: Record<string, string> = s.marks || {};
    for (const [sid, m] of Object.entries(marks)) {
      const st = stu.get(sid);
      attendance.push({
        "بەروار": s.date, "قۆناغ": stageName(sb?.stage ?? st?.stage), "وانە": sb?.name || "", "شوعبە": s.section,
        "خوێندکار": st?.name || sid, "دۆخ": MARK[m] || m, "تۆمارکەر": pname(s.recorded_by),
      });
      const k = sid + "|" + s.subject_id;
      const t = tally.get(k) || { stage: sb?.stage ?? st?.stage ?? 0, student: st?.name || sid, subject: sb?.name || "", a: 0, l: 0, e: 0, n: 0 };
      t.n++; if (m === "a" || m === "l" || m === "e") t[m]++;
      tally.set(k, t);
    }
  }
  const absences = [...tally.values()].sort((a, b) => a.stage - b.stage || byKu(a.student, b.student) || byKu(a.subject, b.subject))
    .map((t) => ({ "قۆناغ": stageName(t.stage), "خوێندکار": t.student, "وانە": t.subject, "غائب": t.a, "دواکەوتوو": t.l, "مۆڵەت": t.e, "وانەی تۆمارکراو": t.n }));

  const wb = XLSX.utils.book_new();
  const add = (name: string, rows: Row[], widths: number[]) => {
    const ws = rows.length ? XLSX.utils.json_to_sheet(rows) : XLSX.utils.aoa_to_sheet([["—"]]);
    ws["!cols"] = widths.map((w) => ({ wch: w }));
    XLSX.utils.book_append_sheet(wb, ws, name);
  };
  add("غیابات", absences, [10, 30, 34, 8, 11, 8, 15]);
  add("ئامادەبوون", attendance, [12, 10, 34, 7, 30, 11, 18]);
  add("خوێندکاران", students, [10, 7, 32, 12]);
  add("وانەکان", subjects, [10, 36, 12, 36]);
  add("مامۆستایان", teachers, [22, 16, 12, 50]);
  wb.Workbook = { Views: [{ RTL: true }] } as any;
  return new Uint8Array(XLSX.write(wb, { type: "array", bookType: "xlsx" }) as ArrayBuffer);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  let token = Deno.env.get("TELEGRAM_BOT_TOKEN") || "";
  const clean = (s: unknown) => (token ? String(s).split(token).join("***") : String(s)).slice(0, 400);
  const tg = async (method: string, body: FormData | Record<string, unknown>) => {
    const isForm = body instanceof FormData;
    const r = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
      method: "POST", body: isForm ? body : JSON.stringify(body),
      headers: isForm ? undefined : { "Content-Type": "application/json" },
    });
    const j = await r.json().catch(() => ({}));
    if (!j.ok) throw new Error("telegram " + method + ": " + (j.description || r.status));
    return j.result;
  };
  try {
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    if (!token) { const { data: vt } = await db.rpc("ecpa_backup_token"); token = typeof vt === "string" ? vt : ""; }
    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");
    const { data: cfg } = await db.from("ecpa_backup_config").select("*").eq("id", 1).maybeSingle();

    // who is calling?
    let caller: "cron" | "admin" | null = null;
    const key = req.headers.get("x-ecpa-key") || "";
    if (key && cfg?.cron_key && key.length === cfg.cron_key.length && key === cfg.cron_key) caller = "cron";
    else {
      const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      if (jwt) {
        const { data: who } = await db.auth.getUser(jwt);
        if (who?.user) {
          const { data: me } = await db.from("ecpa_profiles").select("role").eq("id", who.user.id).maybeSingle();
          if (me?.role === "admin") caller = "admin";
        }
      }
    }
    if (!caller) return json({ error: "forbidden" }, 403);
    if (caller === "cron" && !["run", "dry", "link"].includes(action)) return json({ error: "forbidden" }, 403);

    if (action === "status") {
      const { data: last } = await db.from("ecpa_backups").select("created_at,ok,trigger,detail").order("created_at", { ascending: false }).limit(1).maybeSingle();
      const bot = token && !cfg?.chat_id ? ((await tg("getMe", {}).catch(() => null)) as Row | null)?.username || null : null;
      return json({ configured: !!token, bot, chat: cfg?.chat_id ? { name: cfg.chat_name || "" } : null, last: last || null });
    }
    const build = async () => {
      const data: Record<string, Row[]> = {};
      for (const [t, order] of TABLES) data[t] = await fetchAll(db, t, order);
      const now = new Date();
      const day = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Baghdad", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
      const counts = {
        students: data.ecpa_students.length,
        subjects: data.ecpa_subjects.length,
        teachers: data.ecpa_profiles.filter((p) => p.role !== "admin").length,
        sessions: data.ecpa_sessions.length,
        sessions_today: data.ecpa_sessions.filter((s) => s.date === day).length,
        marks: data.ecpa_sessions.reduce((n, s) => n + Object.keys(s.marks || {}).length, 0),
      };
      const full = new TextEncoder().encode(JSON.stringify({ app: "ECPA", kind: "backup", version: 1, created_at: now.toISOString(), counts, tables: data }));
      return { day, counts, full, xlsx: workbook(data) };
    };
    if (action === "dry") {
      const b = await build();
      return json({ ok: true, day: b.day, counts: b.counts, json_bytes: b.full.length, xlsx_bytes: b.xlsx.length, token: !!token, chat: !!cfg?.chat_id });
    }
    if (!token) return json({ error: "no_token" }, 400);

    // the chat that most recently wrote to the bot (after the admin presses Start)
    const linkChat = async (): Promise<{ id: number; name: string } | null> => {
      const ups: Row[] = await tg("getUpdates", { limit: 100, allowed_updates: ["message"] });
      const chats = ups.map((u) => u.message?.chat).filter((c) => c && c.type === "private");
      if (!chats.length) return null;
      const c = chats[chats.length - 1];
      const name = [c.first_name, c.last_name].filter(Boolean).join(" ") + (c.username ? " (@" + c.username + ")" : "");
      await db.from("ecpa_backup_config").update({ chat_id: c.id, chat_name: name, updated_at: new Date().toISOString() }).eq("id", 1);
      await tg("sendMessage", {
        chat_id: c.id,
        text: "✅ پاشەکەوتی ECPA بەم چاتە بەسترایەوە.\nهەموو شەوێک کاتژمێر ١١ پاشەکەوتێکی هەموو داتاکان لێرە دەنێردرێت.",
      });
      return { id: c.id, name };
    };

    if (action === "link") {
      const c = await linkChat();
      if (!c) return json({ error: "no_start" }, 400);
      return json({ ok: true, chat: { name: c.name } });
    }

    if (action === "run") {
      const trigger = caller === "cron" ? "cron" : "manual";
      const log = (ok: boolean, detail: string, counts: Row | null) =>
        db.from("ecpa_backups").insert({ trigger, ok, detail: clean(detail), counts });
      let chatId = cfg?.chat_id;
      if (!chatId) { const c = await linkChat().catch(() => null); if (c) chatId = c.id; }
      if (!chatId) { await log(false, "no_chat", null); return json({ error: "no_chat" }, 400); }
      try {
        const { day, counts, full, xlsx } = await build();
        const caption = "🗂 پاشەکەوتی ECPA · " + day + "\n" +
          "خوێندکار: " + counts.students + " · وانە: " + counts.subjects + " · مامۆستا: " + counts.teachers + "\n" +
          "وانەی تۆمارکراو: " + counts.sessions + " (ئەمڕۆ: " + counts.sessions_today + ")\n" +
          "📊 ئەم فایلە ئێکسڵە بەبێ ئەپەکەش دەکرێتەوە.";
        const send = async (bytes: Uint8Array, filename: string, mime: string, text: string, silent: boolean) => {
          const fd = new FormData();
          fd.append("chat_id", String(chatId));
          fd.append("document", new Blob([bytes], { type: mime }), filename);
          fd.append("caption", text);
          if (silent) fd.append("disable_notification", "true");
          await tg("sendDocument", fd);
        };
        await send(xlsx, "ECPA-" + day + ".xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", caption, false);
        await send(full, "ECPA-backup-" + day + ".json", "application/json", "📦 فایلی پاشەکەوتی تەواو. هەڵیبگرە.\nبۆ گەڕاندنەوەی داتا: ئەم فایلە دابەزێنە، پاشان لە ئەپەکە بڕۆ بۆ ڕێکخستن ← گەڕاندنەوەی داتا لە پاشەکەوت و ئەم فایلە هەڵبژێرە.", true);
        await log(true, "sent", counts);
        return json({ ok: true, counts });
      } catch (e) {
        await log(false, String((e as Error)?.message || e), null);
        return json({ error: "send_failed", message: clean((e as Error)?.message || e) }, 502);
      }
    }
    return json({ error: "bad_action" }, 400);
  } catch (e) {
    return json({ error: "server_error", message: clean((e as Error)?.message || e) }, 500);
  }
});
