import {verifyFirebaseIdToken} from "./auth";
import {
  badRequest,
  corsHeaders,
  jsonError,
  jsonOk,
  notFound,
  rateLimitHeaders,
} from "./errors";
import {Env, handleFinance} from "./finance";
import {IsolatedRateLimitOutcome, UserGate} from "./UserGate";

export {UserGate};

const FINANCE_PREFIX = "/api/finance/";

function rateLimitProbeResponse(
  outcome: IsolatedRateLimitOutcome,
  successMessage: string,
): Response {
  if (!outcome.ok) {
    const retryAfterSec = Math.max(
      1,
      Math.ceil((outcome.info.resetAt - Date.now()) / 1000),
    );
    const headers = new Headers(
      rateLimitHeaders({
        bucket: outcome.info.bucket,
        limit: outcome.info.limit,
        remaining: 0,
        resetAt: outcome.info.resetAt,
      }),
    );
    new Headers(corsHeaders()).forEach((value, key) => {
      headers.set(key, value);
    });
    headers.set("Retry-After", String(retryAfterSec));
    return Response.json(
      {
        error: {
          code: outcome.code,
          message: outcome.message,
        },
      },
      {status: 429, headers},
    );
  }

  const info = outcome.info;
  return jsonOk(
    {
      success: true,
      message: successMessage,
      bucket: info.bucket,
      limit: info.limit,
      remaining: info.remaining,
      count: info.count,
    },
    200,
    rateLimitHeaders(info),
  );
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, {status: 204, headers: corsHeaders()});
      }

      const url = new URL(request.url);

      if (request.method === "GET" && (url.pathname === "/" || url.pathname === "")) {
        return jsonOk({
          service: "journey-to-balance-api",
          status: "ok",
          auth: "Firebase ID token required for /api/finance/* and /api/test/*",
        });
      }

      if (request.method === "GET" && url.pathname === "/health") {
        return jsonOk({ok: true});
      }

      const projectId = env.FIREBASE_PROJECT_ID || "journey-to-balance";

      // Non-mutating auth probe: verifies Firebase ID token and returns UID.
      // Does not read or write any financial data.
      if (
        request.method === "GET" &&
        (url.pathname === "/api/auth/me" || url.pathname === "/api/auth/me/")
      ) {
        const user = await verifyFirebaseIdToken(request, projectId);
        return jsonOk({
          authenticated: true,
          uid: user.uid,
          emailPresent: Boolean(user.email),
        });
      }

      // Non-mutating rate-limit probe (isolated Durable Object bucket).
      if (
        request.method === "GET" &&
        (url.pathname === "/api/test/rate-limit" ||
          url.pathname === "/api/test/rate-limit/")
      ) {
        const user = await verifyFirebaseIdToken(request, projectId);
        const gate = env.USER_GATE.get(env.USER_GATE.idFromName(user.uid));
        const outcome = await gate.enforceIsolatedTestRateLimit();
        return rateLimitProbeResponse(outcome, "Rate limit test passed");
      }

      // Temporary: probe production addMoney bucket (same DO / keys / window).
      // Does not touch Firestore. Shares counters with real Add Money.
      if (
        request.method === "GET" &&
        (url.pathname === "/api/test/rate-limit-add-money" ||
          url.pathname === "/api/test/rate-limit-add-money/")
      ) {
        const user = await verifyFirebaseIdToken(request, projectId);
        const gate = env.USER_GATE.get(env.USER_GATE.idFromName(user.uid));
        const outcome = await gate.enforceRateLimitsOutcome("addMoney");
        return rateLimitProbeResponse(
          outcome,
          "addMoney rate limit probe (non-mutating)",
        );
      }

      if (!url.pathname.startsWith(FINANCE_PREFIX)) {
        throw notFound("Not found.");
      }

      if (request.method !== "POST") {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: corsHeaders(),
        });
      }

      const user = await verifyFirebaseIdToken(request, projectId);
      const route = url.pathname.slice(FINANCE_PREFIX.length).replace(/\/$/, "");

      let body: Record<string, unknown> = {};
      const text = await request.text();
      if (text.trim()) {
        const parsed: unknown = JSON.parse(text);
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
          return jsonError(new Error("Invalid JSON body"));
        }
        body = parsed as Record<string, unknown>;
      }

      // Never trust client-supplied identity fields.
      delete body.uid;
      delete body.userId;
      delete body.email;

      const result = await handleFinance(env, user.uid, route, body);
      return jsonOk(result);
    } catch (error) {
      if (error instanceof SyntaxError) {
        return jsonError(badRequest("Invalid JSON body"));
      }
      return jsonError(error);
    }
  },
} satisfies ExportedHandler<Env>;
