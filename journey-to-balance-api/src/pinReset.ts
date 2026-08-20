import type {AuthUser} from "./auth";
import {
  badRequest,
  internal,
  RateLimitExceededError,
} from "./errors";
import type {Env} from "./finance";
import {FirestoreClient} from "./firestore";
import type {RateBucketName} from "./rateLimit";

const OTP_TTL_MS = 10 * 60 * 1000;
const OTP_RESEND_MS = 30_000;
const OTP_MAX_ATTEMPTS = 5;
const OTP_DOC = ["security", "pinOtp"] as const;

function normalizeEmail(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim().toLowerCase();
}

function randomOtp(): string {
  const bytes = new Uint8Array(2);
  crypto.getRandomValues(bytes);
  const n = (bytes[0] << 8) | bytes[1];
  return String(n % 10000).padStart(4, "0");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function hashOtp(uid: string, otp: string): Promise<string> {
  return sha256Hex(`${uid}:${otp}`);
}

function client(env: Env): FirestoreClient {
  if (!env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    throw internal(
      "Server misconfigured: FIREBASE_SERVICE_ACCOUNT_JSON is not set.",
    );
  }
  return new FirestoreClient(
    env.FIREBASE_PROJECT_ID,
    env.FIREBASE_SERVICE_ACCOUNT_JSON,
  );
}

async function enforceLimit(env: Env, uid: string, bucket: RateBucketName) {
  const gate = env.USER_GATE.get(env.USER_GATE.idFromName(uid));
  const outcome = await gate.enforceRateLimitsOutcome(bucket);
  if (!outcome.ok) {
    throw new RateLimitExceededError(
      {
        bucket: outcome.info.bucket,
        limit: outcome.info.limit,
        remaining: outcome.info.remaining,
        resetAt: outcome.info.resetAt,
      },
      outcome.message,
    );
  }
}

function requireAccountEmail(user: AuthUser, typedEmail: string): string {
  const account = normalizeEmail(user.email);
  if (!account) {
    throw badRequest("Your Google account has no email to send a code to.");
  }
  if (!typedEmail) {
    throw badRequest("Enter the Gmail you use to sign in.");
  }
  if (typedEmail !== account) {
    throw badRequest("This email doesn't match the signed-in account.");
  }
  return account;
}

async function sendOtpEmail(env: Env, to: string, otp: string): Promise<void> {
  const apiKey = env.RESEND_API_KEY?.trim();
  if (!apiKey) {
    throw internal("PIN reset email is not configured.");
  }

  const from = `Journey to Balance <onboarding@${"resend"}.dev>`;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: "Your Journey to Balance PIN reset code",
      text:
        `Your 4-digit code is ${otp}. It expires in 10 minutes.\n\n` +
        `If you didn't request this, you can ignore this email.`,
      html:
        `<p>Your 4-digit Journey to Balance code is:</p>` +
        `<p style="font-size:28px;font-weight:700;letter-spacing:8px">${otp}</p>` +
        `<p>It expires in 10 minutes. If you didn't request this, you can ignore this email.</p>`,
    }),
  });

  if (!res.ok) {
    console.error("Resend failed", await res.text());
    throw internal("Could not send the code. Please try again.");
  }
}

export async function handlePinReset(
  env: Env,
  user: AuthUser,
  route: string,
  body: Record<string, unknown>,
): Promise<unknown> {
  const typedEmail = normalizeEmail(body.email);

  if (route === "request") {
    const email = requireAccountEmail(user, typedEmail);
    await enforceLimit(env, user.uid, "pinResetRequest");

    const db = client(env);
    const existing = await db.getSubDoc(user.uid, ...OTP_DOC);
    const lastSentAt =
      typeof existing?.sentAtMs === "number" ? existing.sentAtMs : 0;
    if (Date.now() - lastSentAt < OTP_RESEND_MS) {
      throw badRequest("Wait a moment before requesting another code.");
    }

    const otp = randomOtp();
    const hash = await hashOtp(user.uid, otp);
    const now = Date.now();
    await db.setSubDoc(user.uid, [...OTP_DOC], {
      hash,
      expiresAtMs: now + OTP_TTL_MS,
      sentAtMs: now,
      attempts: 0,
    });

    try {
      await sendOtpEmail(env, email, otp);
    } catch (error) {
      await db.deleteSubDoc(user.uid, ...OTP_DOC);
      throw error;
    }

    return {sent: true};
  }

  if (route === "verify") {
    const otp = typeof body.otp === "string" ? body.otp.trim() : "";
    if (!/^\d{4}$/.test(otp)) {
      throw badRequest("Enter the 4-digit code from your email.");
    }
    requireAccountEmail(user, typedEmail);
    await enforceLimit(env, user.uid, "pinResetVerify");

    const db = client(env);
    const stored = await db.getSubDoc(user.uid, ...OTP_DOC);
    if (!stored) {
      throw badRequest("Request a new code first.");
    }

    const expiresAtMs =
      typeof stored.expiresAtMs === "number" ? stored.expiresAtMs : 0;
    if (Date.now() > expiresAtMs) {
      await db.deleteSubDoc(user.uid, ...OTP_DOC);
      throw badRequest("That code expired. Request a new one.");
    }

    const attempts =
      typeof stored.attempts === "number" ? stored.attempts : 0;
    if (attempts >= OTP_MAX_ATTEMPTS) {
      await db.deleteSubDoc(user.uid, ...OTP_DOC);
      throw badRequest("Too many attempts. Request a new code.");
    }

    const expected = typeof stored.hash === "string" ? stored.hash : "";
    const actual = await hashOtp(user.uid, otp);
    if (actual !== expected) {
      await db.setSubDoc(user.uid, [...OTP_DOC], {
        ...stored,
        attempts: attempts + 1,
      });
      throw badRequest("Incorrect code. Try again.");
    }

    await db.deleteSubDoc(user.uid, ...OTP_DOC);
    return {verified: true};
  }

  throw badRequest("Unknown PIN reset step.");
}
