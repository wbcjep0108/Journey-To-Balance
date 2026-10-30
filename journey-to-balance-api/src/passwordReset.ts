import {getGoogleAccessToken, FirestoreClient} from "./firestore";
import type {Env} from "./finance";
import {consumeDailyEmailAllowance} from "./protection";
import {RATE_LIMIT_CONFIG} from "./rateLimit";
import {renderPasswordResetEmail} from "./passwordResetEmail";
import type {UserGate} from "./UserGate";

const CODE_TTL_MS = 10 * 60 * 1000;
const TOKEN_TTL_MS = 10 * 60 * 1000;
const RESEND_MS = 30_000;
const MAX_ATTEMPTS = 5;
const OPERATION_LOCK_MS = 30_000;
const RECORD_PATH = ["security", "passwordReset"] as const;
const FALLBACK_LOOKUP_EMAIL = "invalid@invalid.example";

export interface PasswordResetAccount {
  localId: string;
  hasPassword: boolean;
}

export interface PasswordResetRecord {
  kind: "code" | "token";
  hash: string;
  expiresAtMs: number;
  createdAtMs: number;
  attempts?: number;
}

export interface PasswordResetDependencies {
  lookupAccount(email: string): Promise<PasswordResetAccount | null>;
  getRecord(localId: string): Promise<PasswordResetRecord | null>;
  setRecord(localId: string, record: PasswordResetRecord): Promise<void>;
  deleteRecord(localId: string): Promise<void>;
  updatePassword(localId: string, password: string): Promise<void>;
  revokeRefreshTokens(localId: string): Promise<void>;
  sendCode(email: string, code: string): Promise<void>;
  allowRequest(email: string, ip: string): Promise<boolean>;
  allowDailyEmail(email: string): Promise<boolean>;
  acquireLock(email: string): Promise<boolean>;
  releaseLock(email: string): Promise<void>;
  hmacSecret: string;
  now(): number;
  generateCode(): string;
  generateToken(): string;
}

export class PasswordResetPublicError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
    this.name = "PasswordResetPublicError";
  }
}

export function normalizePasswordResetEmail(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

export function isValidPasswordResetEmail(email: string): boolean {
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function randomCode(): string {
  const digits: number[] = [];
  while (digits.length < 6) {
    const bytes = crypto.getRandomValues(new Uint8Array(6 - digits.length));
    for (const byte of bytes) {
      if (byte < 250) digits.push(byte % 10);
    }
  }
  return digits.slice(0, 6).join("");
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacHex(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    {name: "HMAC", hash: "SHA-256"},
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  const max = Math.max(left.length, right.length);
  let difference = left.length ^ right.length;
  for (let index = 0; index < max; index++) {
    difference |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return difference === 0;
}

function hashCode(deps: PasswordResetDependencies, email: string, code: string) {
  return hmacHex(deps.hmacSecret, `password-reset-code:${email}:${code}`);
}

function hashToken(deps: PasswordResetDependencies, email: string, token: string) {
  return hmacHex(deps.hmacSecret, `password-reset-token:${email}:${token}`);
}

export async function requestPasswordReset(
  deps: PasswordResetDependencies,
  rawEmail: unknown,
  ip: string,
): Promise<{ok: true}> {
  const email = normalizePasswordResetEmail(rawEmail);
  const lookupEmail = isValidPasswordResetEmail(email) ? email : FALLBACK_LOOKUP_EMAIL;

  try {
    const [allowed, account, code] = await Promise.all([
      deps.allowRequest(email, ip),
      deps.lookupAccount(lookupEmail),
      Promise.resolve(deps.generateCode()),
    ]);
    const hash = await hashCode(deps, email, code);
    if (!allowed || !isValidPasswordResetEmail(email) || !account?.hasPassword) {
      return {ok: true};
    }

    const existing = await deps.getRecord(account.localId);
    const now = deps.now();
    if (existing?.kind === "code" && now - existing.createdAtMs < RESEND_MS) {
      return {ok: true};
    }
    if (!await deps.allowDailyEmail(email)) return {ok: true};

    await deps.setRecord(account.localId, {
      kind: "code",
      hash,
      expiresAtMs: now + CODE_TTL_MS,
      createdAtMs: now,
      attempts: 0,
    });
    try {
      await deps.sendCode(email, code);
    } catch (_) {
      await deps.deleteRecord(account.localId).catch(() => undefined);
    }
  } catch (_) {
    // Request responses are deliberately indistinguishable.
  }
  return {ok: true};
}

export async function verifyPasswordResetCode(
  deps: PasswordResetDependencies,
  rawEmail: unknown,
  rawCode: unknown,
): Promise<{resetToken: string; expiresIn: number}> {
  const email = normalizePasswordResetEmail(rawEmail);
  const code = typeof rawCode === "string" ? rawCode.trim() : "";
  if (!isValidPasswordResetEmail(email) || !/^\d{6}$/.test(code)) {
    throw new PasswordResetPublicError(400, "invalid_code");
  }

  if (!await deps.acquireLock(email)) {
    throw new PasswordResetPublicError(400, "invalid_code");
  }
  try {

  const account = await deps.lookupAccount(email).catch(() => null);
  if (!account?.hasPassword) throw new PasswordResetPublicError(400, "invalid_code");
  const record = await deps.getRecord(account.localId).catch(() => null);
  const now = deps.now();
  if (!record || record.kind !== "code" || now > record.expiresAtMs) {
    if (record?.kind === "code") await deps.deleteRecord(account.localId).catch(() => undefined);
    throw new PasswordResetPublicError(400, "invalid_code");
  }

  const actual = await hashCode(deps, email, code);
  if (!constantTimeEqual(record.hash, actual)) {
    const attempts = (record.attempts ?? 0) + 1;
    if (attempts >= MAX_ATTEMPTS) {
      await deps.deleteRecord(account.localId);
    } else {
      await deps.setRecord(account.localId, {...record, attempts});
    }
    throw new PasswordResetPublicError(400, "invalid_code");
  }

  const resetToken = deps.generateToken();
  await deps.setRecord(account.localId, {
    kind: "token",
    hash: await hashToken(deps, email, resetToken),
    expiresAtMs: now + TOKEN_TTL_MS,
    createdAtMs: now,
  });
  return {resetToken, expiresIn: TOKEN_TTL_MS / 1000};
  } finally {
    await deps.releaseLock(email).catch(() => undefined);
  }
}

export async function confirmPasswordReset(
  deps: PasswordResetDependencies,
  rawEmail: unknown,
  rawToken: unknown,
  rawPassword: unknown,
): Promise<{ok: true}> {
  const email = normalizePasswordResetEmail(rawEmail);
  const token = typeof rawToken === "string" ? rawToken.trim() : "";
  const password = typeof rawPassword === "string" ? rawPassword : "";
  if (password.length < 8) throw new PasswordResetPublicError(400, "weak_password");
  if (!isValidPasswordResetEmail(email) || !token) {
    throw new PasswordResetPublicError(400, "invalid_token");
  }

  if (!await deps.acquireLock(email)) {
    throw new PasswordResetPublicError(400, "invalid_token");
  }
  try {

  const account = await deps.lookupAccount(email).catch(() => null);
  if (!account?.hasPassword) throw new PasswordResetPublicError(400, "invalid_token");
  const record = await deps.getRecord(account.localId).catch(() => null);
  const now = deps.now();
  if (!record || record.kind !== "token" || now > record.expiresAtMs) {
    if (record?.kind === "token") await deps.deleteRecord(account.localId).catch(() => undefined);
    throw new PasswordResetPublicError(400, "invalid_token");
  }
  const actual = await hashToken(deps, email, token);
  if (!constantTimeEqual(record.hash, actual)) {
    throw new PasswordResetPublicError(400, "invalid_token");
  }

  await deps.updatePassword(account.localId, password);
  await deps.revokeRefreshTokens(account.localId);
  await deps.deleteRecord(account.localId);
  return {ok: true};
  } finally {
    await deps.releaseLock(email).catch(() => undefined);
  }
}

class IdentityToolkitClient {
  constructor(
    private readonly projectId: string,
    private readonly serviceAccountJson: string,
  ) {}

  private async post(path: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
    const token = await getGoogleAccessToken(this.serviceAccountJson, [
      "https://www.googleapis.com/auth/cloud-platform",
    ]);
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/projects/${this.projectId}/accounts:${path}`,
      {
        method: "POST",
        headers: {Authorization: `Bearer ${token}`, "Content-Type": "application/json"},
        body: JSON.stringify(body),
      },
    );
    if (!response.ok) throw new Error("Identity Toolkit request failed.");
    return await response.json() as Record<string, unknown>;
  }

  async lookup(email: string): Promise<PasswordResetAccount | null> {
    const result = await this.post("lookup", {email: [email]});
    const users = Array.isArray(result.users) ? result.users : [];
    const user = users[0] as Record<string, unknown> | undefined;
    if (!user) return null;
    const localId = typeof user.localId === "string" ? user.localId : "";
    if (!localId) return null;
    const providers = Array.isArray(user.providerUserInfo) ? user.providerUserInfo : [];
    const hasPasswordProvider = providers.some((provider) =>
      typeof provider === "object" && provider !== null &&
      (provider as Record<string, unknown>).providerId === "password",
    );
    return {
      localId,
      hasPassword: hasPasswordProvider || typeof user.passwordHash === "string",
    };
  }

  async updatePassword(localId: string, password: string): Promise<void> {
    await this.post("update", {localId, password, returnSecureToken: false});
  }

  async revokeRefreshTokens(localId: string): Promise<void> {
    await this.post("update", {
      localId,
      validSince: String(Math.floor(Date.now() / 1000)),
      returnSecureToken: false,
    });
  }
}

function parseRecord(value: Record<string, unknown> | null): PasswordResetRecord | null {
  if (!value || (value.kind !== "code" && value.kind !== "token") ||
      typeof value.hash !== "string" || typeof value.expiresAtMs !== "number" ||
      typeof value.createdAtMs !== "number") return null;
  return {
    kind: value.kind,
    hash: value.hash,
    expiresAtMs: value.expiresAtMs,
    createdAtMs: value.createdAtMs,
    attempts: typeof value.attempts === "number" ? value.attempts : undefined,
  };
}

async function sendPasswordResetEmail(env: Env, email: string, code: string): Promise<void> {
  const apiKey = env.BREVO_API_KEY?.trim();
  const senderEmail = env.BREVO_SENDER_EMAIL?.trim();
  const senderName = env.BREVO_SENDER_NAME?.trim();
  if (!apiKey || !senderEmail || !senderName) throw new Error("Email is not configured.");
  const rendered = renderPasswordResetEmail({code, minutes: CODE_TTL_MS / 60_000});
  const response = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {"api-key": apiKey, "Content-Type": "application/json"},
    body: JSON.stringify({
      sender: {email: senderEmail, name: senderName},
      to: [{email}],
      subject: rendered.subject,
      textContent: rendered.text,
      htmlContent: rendered.html,
    }),
  });
  if (!response.ok) throw new Error("Email delivery failed.");
}

function gate(env: Env, name: string): DurableObjectStub<UserGate> {
  return env.USER_GATE.get(env.USER_GATE.idFromName(name));
}

export function createPasswordResetDependencies(env: Env): PasswordResetDependencies {
  if (!env.FIREBASE_SERVICE_ACCOUNT_JSON) throw new Error("Service account is not configured.");
  const identity = new IdentityToolkitClient(env.FIREBASE_PROJECT_ID, env.FIREBASE_SERVICE_ACCOUNT_JSON);
  const firestore = new FirestoreClient(env.FIREBASE_PROJECT_ID, env.FIREBASE_SERVICE_ACCOUNT_JSON);
  return {
    lookupAccount: (email) => identity.lookup(email),
    getRecord: async (localId) => parseRecord(await firestore.getSubDoc(localId, ...RECORD_PATH)),
    setRecord: (localId, record) => firestore.setSubDoc(
      localId,
      [...RECORD_PATH],
      {...record},
    ),
    deleteRecord: (localId) => firestore.deleteSubDoc(localId, ...RECORD_PATH),
    updatePassword: (localId, password) => identity.updatePassword(localId, password),
    revokeRefreshTokens: (localId) => identity.revokeRefreshTokens(localId),
    sendCode: (email, code) => sendPasswordResetEmail(env, email, code),
    allowRequest: async (email, ip) => {
      const [emailKey, ipKey] = await Promise.all([
        sha256Hex(`password-reset-email:${email}`),
        sha256Hex(`password-reset-ip:${ip || "unknown"}`),
      ]);
      const [emailAllowed, ipAllowed] = await Promise.all([
        gate(env, `password-reset-email:${emailKey}`).consumePublicRateLimit(
          RATE_LIMIT_CONFIG.passwordResetPerHour.email,
          RATE_LIMIT_CONFIG.windows.passwordResetHourMs,
        ),
        gate(env, `password-reset-ip:${ipKey}`).consumePublicRateLimit(
          RATE_LIMIT_CONFIG.passwordResetPerHour.ip,
          RATE_LIMIT_CONFIG.windows.passwordResetHourMs,
        ),
      ]);
      return emailAllowed && ipAllowed;
    },
    allowDailyEmail: async (email) =>
      (await consumeDailyEmailAllowance(env, email)).ok,
    acquireLock: async (email) => {
      const emailKey = await sha256Hex(`password-reset-email:${email}`);
      return gate(env, `password-reset-email:${emailKey}`).acquirePublicLock(
        OPERATION_LOCK_MS,
      );
    },
    releaseLock: async (email) => {
      const emailKey = await sha256Hex(`password-reset-email:${email}`);
      await gate(env, `password-reset-email:${emailKey}`).releasePublicLock();
    },
    hmacSecret: env.FIREBASE_SERVICE_ACCOUNT_JSON,
    now: () => Date.now(),
    generateCode: randomCode,
    generateToken: randomToken,
  };
}
