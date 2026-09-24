import { timingSafeEqual } from "node:crypto";
import http from "node:http";

import Anthropic from "@anthropic-ai/sdk";

const PORT = Number(process.env.PORT ?? 8787);
/** Shared secret the app sends as `X-App-Token`. Leave empty to disable (local testing only). */
const APP_TOKEN = process.env.APP_TOKEN ?? "";
const MODEL = process.env.COACH_MODEL ?? "claude-opus-5";
const MAX_MESSAGES = 30;
const MAX_CHARS = 2000;
const RATE_LIMIT = { windowMs: 10 * 60 * 1000, max: 30 };

const client = new Anthropic(); // reads ANTHROPIC_API_KEY

const SYSTEM_PROMPT = `You are Coach, the voice coach inside Floor Age, a fitness app popular in India. Floor Age measures "how old your body moves" with four at-home tests (sit to rise from the floor, one-leg balance, 30-second chair stand, toe reach) and gives a short daily session led by an animated coach.

Your replies are read aloud by text-to-speech, so write the way a friendly trainer talks: two to four short sentences, plain words, no lists, no markdown, no emojis.

Help with movement, exercise, recovery, sleep and everyday healthy habits, including Indian food and routines (early walks before the heat, festival weeks, fasting days). When someone is short on time, tired or sore, suggest a realistic smaller version of today's session using the app's exercises: March in Place, Side Arm Raise, Squat, Chair Stand, Sit to Rise, One-Leg Balance, Side Leg Raise, Calf Raise, Toe Reach, Deep Squat Hold.

You are not a doctor. Don't diagnose or discuss medication. If someone mentions chest pain, fainting, severe breathlessness, sudden weakness or pain that is sharp or getting worse, tell them to stop exercising and get medical help, and to call 112 in an emergency. Respect any limitations listed below and never push through pain. Be warm and encouraging, never shaming; celebrate showing up more than perfect scores.`;

type ChatMessage = { role: "user" | "assistant"; content: string };
type CoachContext = {
  age?: number;
  floorAge?: number;
  weakestArea?: string;
  limitations?: string[];
  sessionsThisWeek?: number;
};

function describeContext(ctx: CoachContext): string {
  const facts: string[] = [];
  if (ctx.age) facts.push(`Age ${ctx.age}.`);
  if (ctx.floorAge) facts.push(`Latest Floor Age ${ctx.floorAge}.`);
  if (ctx.weakestArea) facts.push(`Weakest area: ${ctx.weakestArea}.`);
  if (ctx.limitations?.length) facts.push(`Limitations: ${ctx.limitations.join(", ")}.`);
  if (typeof ctx.sessionsThisWeek === "number") facts.push(`Sessions in the last 7 days: ${ctx.sessionsThisWeek}.`);
  return facts.length ? `About this person: ${facts.join(" ")}` : "Nothing is known about this person yet.";
}

function parseBody(raw: unknown): { messages: ChatMessage[]; context: CoachContext } | string {
  if (typeof raw !== "object" || raw === null) return "Body must be a JSON object.";
  const { messages, context } = raw as { messages?: unknown; context?: unknown };
  if (!Array.isArray(messages) || messages.length === 0) return "messages must be a non-empty array.";
  const recent = messages.slice(-MAX_MESSAGES);
  const clean: ChatMessage[] = [];
  for (const m of recent) {
    const { role, content } = (m ?? {}) as { role?: unknown; content?: unknown };
    if ((role !== "user" && role !== "assistant") || typeof content !== "string" || !content.trim()) {
      return "Each message needs a role (user or assistant) and text content.";
    }
    clean.push({ role, content: content.slice(0, MAX_CHARS) });
  }
  while (clean.length && clean[0].role !== "user") clean.shift();
  if (!clean.length || clean[clean.length - 1].role !== "user") return "The last message must be from the user.";

  const c = (typeof context === "object" && context !== null ? context : {}) as Record<string, unknown>;
  const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.round(v) : undefined);
  return {
    messages: clean,
    context: {
      age: num(c.age),
      floorAge: num(c.floorAge),
      weakestArea: typeof c.weakestArea === "string" ? c.weakestArea.slice(0, 60) : undefined,
      limitations: Array.isArray(c.limitations)
        ? c.limitations.filter((l): l is string => typeof l === "string").slice(0, 10).map((l) => l.slice(0, 40))
        : [],
      sessionsThisWeek: num(c.sessionsThisWeek),
    },
  };
}

async function coachReply(messages: ChatMessage[], context: CoachContext): Promise<string> {
  const response = await client.beta.messages.create({
    model: MODEL,
    max_tokens: 16000,
    // If the model declines, the API re-runs the request on a suitable fallback model.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    // Short conversational replies: low effort keeps them fast for voice.
    output_config: { effort: "low" },
    system: `${SYSTEM_PROMPT}\n\n${describeContext(context)}`,
    messages,
  });

  if (response.stop_reason === "refusal") {
    return "That's not something I can help with. Let's keep the focus on your movement today.";
  }
  const text = response.content
    .filter((block): block is Anthropic.Beta.BetaTextBlock => block.type === "text")
    .map((block) => block.text)
    .join("")
    .trim();
  return text || "Sorry, I lost my words there. Could you ask that again?";
}

// --- HTTP ---------------------------------------------------------------------------------

const hits = new Map<string, number[]>();

function rateLimited(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < RATE_LIMIT.windowMs);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > RATE_LIMIT.max;
}

function tokenOk(header: string | string[] | undefined): boolean {
  if (!APP_TOKEN) return true;
  const given = Buffer.from(typeof header === "string" ? header : "");
  const expected = Buffer.from(APP_TOKEN);
  return given.length === expected.length && timingSafeEqual(given, expected);
}

function send(res: http.ServerResponse, status: number, body: object) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

async function readJson(req: http.IncomingMessage, limit = 64 * 1024): Promise<unknown> {
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > limit) throw new Error("too large");
    chunks.push(chunk as Buffer);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") return send(res, 200, { ok: true });
  if (req.method !== "POST" || req.url !== "/coach") return send(res, 404, { error: "Not found." });

  if (!tokenOk(req.headers["x-app-token"])) return send(res, 401, { error: "Invalid app token." });
  const ip = (req.headers["x-forwarded-for"] as string | undefined)?.split(",")[0].trim() ?? req.socket.remoteAddress ?? "?";
  if (rateLimited(ip)) return send(res, 429, { error: "You're chatting fast! Take a breath and try again in a few minutes." });

  let parsed: ReturnType<typeof parseBody>;
  try {
    parsed = parseBody(await readJson(req));
  } catch {
    return send(res, 400, { error: "Invalid JSON body." });
  }
  if (typeof parsed === "string") return send(res, 400, { error: parsed });

  try {
    const reply = await coachReply(parsed.messages, parsed.context);
    send(res, 200, { reply });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) {
      send(res, 503, { error: "The coach is busy right now. Please try again in a minute." });
    } else if (error instanceof Anthropic.AuthenticationError) {
      console.error("Anthropic authentication failed: check ANTHROPIC_API_KEY");
      send(res, 500, { error: "The coach server isn't configured correctly." });
    } else if (error instanceof Anthropic.APIError) {
      console.error(`Anthropic API error ${error.status}: ${error.message}`);
      send(res, 502, { error: "The coach is unavailable right now. Please try again." });
    } else {
      console.error(error);
      send(res, 500, { error: "Something went wrong. Please try again." });
    }
  }
});

server.listen(PORT, () => {
  console.log(`Floor Age coach server on :${PORT} using ${MODEL}${APP_TOKEN ? "" : " (no APP_TOKEN set)"}`);
});
