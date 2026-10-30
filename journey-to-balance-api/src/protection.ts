import {
  RateLimitExceededError,
  ServiceBusyError,
} from "./errors";
import {
  DAILY_GLOBAL_GATE_NAME,
  DailyLimitOutcome,
  RateBucketName,
} from "./rateLimit";
import type {UserGate} from "./UserGate";

type ProtectionEnv = {
  USER_GATE: DurableObjectNamespace<UserGate>;
};

async function anonymousKey(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function globalGate(env: ProtectionEnv): DurableObjectStub<UserGate> {
  return env.USER_GATE.get(env.USER_GATE.idFromName(DAILY_GLOBAL_GATE_NAME));
}

function throwDailyLimit(outcome: DailyLimitOutcome): never {
  if (outcome.ok) throw new Error("Expected a rejected daily-limit outcome.");
  const info = {
    bucket: outcome.info.bucket,
    limit: outcome.info.limit,
    remaining: outcome.info.remaining,
    resetAt: outcome.info.resetAt,
  };
  if (outcome.status === 503) {
    throw new ServiceBusyError(info, outcome.message);
  }
  throw new RateLimitExceededError(info, outcome.message, outcome.code);
}

/** Minute limits run first; daily pools are untouched when minute checks fail. */
export async function enforceProtectedActionLimits(
  env: ProtectionEnv,
  uid: string,
  bucket: RateBucketName,
): Promise<void> {
  const userGate = env.USER_GATE.get(env.USER_GATE.idFromName(uid));
  const minute = await userGate.enforceRateLimitsOutcome(bucket);
  if (!minute.ok) {
    throw new RateLimitExceededError(
      {
        bucket: minute.info.bucket,
        limit: minute.info.limit,
        remaining: minute.info.remaining,
        resetAt: minute.info.resetAt,
      },
      minute.message,
    );
  }

  const daily = await globalGate(env).consumeProtectedDaily(
    await anonymousKey(`protected-user:${uid}`),
  );
  if (!daily.ok) throwDailyLimit(daily);
}

export async function enforceGlobalProtectedLimit(
  env: ProtectionEnv,
): Promise<void> {
  const outcome = await globalGate(env).consumeGlobalProtectedDaily();
  if (!outcome.ok) throwDailyLimit(outcome);
}

export async function consumeDailyEmailAllowance(
  env: ProtectionEnv,
  email: string,
): Promise<DailyLimitOutcome> {
  return globalGate(env).consumeEmailDaily(
    await anonymousKey(`email-recipient:${email.trim().toLowerCase()}`),
  );
}

export async function enforceDailyEmailLimit(
  env: ProtectionEnv,
  email: string,
): Promise<void> {
  const outcome = await consumeDailyEmailAllowance(env, email);
  if (!outcome.ok) throwDailyLimit(outcome);
}
