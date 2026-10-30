import {rateLimited} from "./errors";

export const RATE_LIMIT_CONFIG = {
  perMinute: {
    general: 60,
    addTransaction: 30,
    updateAvailableBalance: 20,
    receiveSalary: 5,
    addMoney: 5,
    contributeToSavingsGoal: 20,
    deleteTransaction: 20,
    updatePercentages: 10,
    updateTransaction: 30,
    updateMonthlySalary: 20,
    updateSavingsGoalSettings: 20,
    migrateBudgetSchema: 10,
    pinResetRequest: 3,
    pinResetVerify: 10,
    /** Isolated probe; does not share the general or operation counters. */
    rateLimitTest: 5,
  },
  passwordResetPerHour: {
    email: 3,
    ip: 20,
  },
  daily: {
    protectedActionsPerUser: 150,
    protectedRequestsGlobal: 20_000,
    emailsPerRecipient: 5,
    emailsGlobal: 100,
  },
  windows: {
    minuteMs: 60_000,
    passwordResetHourMs: 60 * 60 * 1000,
    manilaUtcOffsetMs: 8 * 60 * 60 * 1000,
    dayMs: 24 * 60 * 60 * 1000,
    dailyStorageTtlMs: 26 * 60 * 60 * 1000,
  },
} as const;

export const RATE_LIMITS = RATE_LIMIT_CONFIG.perMinute;
export const WINDOW_MS = RATE_LIMIT_CONFIG.windows.minuteMs;
export const DAILY_GLOBAL_GATE_NAME = "system:daily-limits:v1";

export type RateBucketName = keyof typeof RATE_LIMITS;

export interface RateBucketState {
  count: number;
  windowStart: number;
}

export interface DailyCounterState {
  count: number;
  expiresAt: number;
}

export interface DailyWindow {
  key: string;
  windowStart: number;
  resetAt: number;
  expiresAt: number;
}

export interface DailyLimitInfo {
  bucket: string;
  limit: number;
  count: number;
  remaining: number;
  windowStart: number;
  resetAt: number;
}

export type DailyLimitOutcome =
  | {
    ok: true;
    global: DailyCounterState;
    scoped?: DailyCounterState;
    info: DailyLimitInfo;
  }
  | {
    ok: false;
    status: 429 | 503;
    code: "daily-rate-limit-exceeded" | "temporarily-busy";
    message: string;
    info: DailyLimitInfo;
  };

/** Fixed daily window at midnight Asia/Manila (UTC+8, no DST). */
export function manilaDailyWindow(now: number): DailyWindow {
  const offset = RATE_LIMIT_CONFIG.windows.manilaUtcOffsetMs;
  const local = new Date(now + offset);
  const year = local.getUTCFullYear();
  const month = local.getUTCMonth();
  const day = local.getUTCDate();
  const windowStart = Date.UTC(year, month, day) - offset;
  const resetAt = windowStart + RATE_LIMIT_CONFIG.windows.dayMs;
  return {
    key: [
      String(year).padStart(4, "0"),
      String(month + 1).padStart(2, "0"),
      String(day).padStart(2, "0"),
    ].join("-"),
    windowStart,
    resetAt,
    expiresAt: windowStart + RATE_LIMIT_CONFIG.windows.dailyStorageTtlMs,
  };
}

function dailyInfo(
  bucket: string,
  limit: number,
  count: number,
  window: DailyWindow,
): DailyLimitInfo {
  return {
    bucket,
    limit,
    count,
    remaining: Math.max(0, limit - count),
    windowStart: window.windowStart,
    resetAt: window.resetAt,
  };
}

function dailyCount(state: DailyCounterState | undefined, now: number): number {
  return state && state.expiresAt > now ? state.count : 0;
}

/** Pure atomic-decision helper for the protected global + per-user pools. */
export function consumeProtectedDailyCounters(
  globalCurrent: DailyCounterState | undefined,
  userCurrent: DailyCounterState | undefined,
  now: number,
): DailyLimitOutcome {
  const window = manilaDailyWindow(now);
  const globalLimit = RATE_LIMIT_CONFIG.daily.protectedRequestsGlobal;
  const userLimit = RATE_LIMIT_CONFIG.daily.protectedActionsPerUser;
  const globalCount = dailyCount(globalCurrent, now);
  const userCount = dailyCount(userCurrent, now);

  if (globalCount >= globalLimit) {
    return {
      ok: false,
      status: 503,
      code: "temporarily-busy",
      message: "The service is busy. Please try again later.",
      info: dailyInfo("dailyProtectedGlobal", globalLimit, globalCount, window),
    };
  }
  if (userCount >= userLimit) {
    return {
      ok: false,
      status: 429,
      code: "daily-rate-limit-exceeded",
      message: "You've reached today's limit. Try again tomorrow.",
      info: dailyInfo("dailyProtectedUser", userLimit, userCount, window),
    };
  }

  const global = {count: globalCount + 1, expiresAt: window.expiresAt};
  const scoped = {count: userCount + 1, expiresAt: window.expiresAt};
  return {
    ok: true,
    global,
    scoped,
    info: dailyInfo("dailyProtectedUser", userLimit, scoped.count, window),
  };
}

/** Pure atomic-decision helper for protected routes without a user-action cap. */
export function consumeGlobalProtectedCounter(
  globalCurrent: DailyCounterState | undefined,
  now: number,
): DailyLimitOutcome {
  const window = manilaDailyWindow(now);
  const limit = RATE_LIMIT_CONFIG.daily.protectedRequestsGlobal;
  const count = dailyCount(globalCurrent, now);
  if (count >= limit) {
    return {
      ok: false,
      status: 503,
      code: "temporarily-busy",
      message: "The service is busy. Please try again later.",
      info: dailyInfo("dailyProtectedGlobal", limit, count, window),
    };
  }
  const global = {count: count + 1, expiresAt: window.expiresAt};
  return {
    ok: true,
    global,
    info: dailyInfo("dailyProtectedGlobal", limit, global.count, window),
  };
}

/** Pure atomic-decision helper for the global + per-recipient email pools. */
export function consumeEmailDailyCounters(
  globalCurrent: DailyCounterState | undefined,
  recipientCurrent: DailyCounterState | undefined,
  now: number,
): DailyLimitOutcome {
  const window = manilaDailyWindow(now);
  const globalLimit = RATE_LIMIT_CONFIG.daily.emailsGlobal;
  const recipientLimit = RATE_LIMIT_CONFIG.daily.emailsPerRecipient;
  const globalCount = dailyCount(globalCurrent, now);
  const recipientCount = dailyCount(recipientCurrent, now);

  if (globalCount >= globalLimit) {
    return {
      ok: false,
      status: 429,
      code: "daily-rate-limit-exceeded",
      message: "You've reached today's limit. Try again tomorrow.",
      info: dailyInfo("dailyEmailGlobal", globalLimit, globalCount, window),
    };
  }
  if (recipientCount >= recipientLimit) {
    return {
      ok: false,
      status: 429,
      code: "daily-rate-limit-exceeded",
      message: "You've reached today's limit. Try again tomorrow.",
      info: dailyInfo(
        "dailyEmailRecipient",
        recipientLimit,
        recipientCount,
        window,
      ),
    };
  }

  const global = {count: globalCount + 1, expiresAt: window.expiresAt};
  const scoped = {count: recipientCount + 1, expiresAt: window.expiresAt};
  return {
    ok: true,
    global,
    scoped,
    info: dailyInfo("dailyEmailRecipient", recipientLimit, scoped.count, window),
  };
}

export function consumeFixedWindow(
  current: RateBucketState | undefined,
  limit: number,
  windowMs: number,
  now: number,
): {allowed: boolean; state: RateBucketState} {
  if (!current || now - current.windowStart >= windowMs) {
    return {allowed: true, state: {count: 1, windowStart: now}};
  }
  if (current.count >= limit) return {allowed: false, state: current};
  return {
    allowed: true,
    state: {count: current.count + 1, windowStart: current.windowStart},
  };
}

/**
 * Fixed one-minute window counter. Pure helper — no I/O.
 * Throws ApiError(429) when the limit is exceeded.
 */
export function nextRateBucket(
  current: RateBucketState | undefined,
  limit: number,
  now: number,
): RateBucketState {
  if (!current || now - current.windowStart >= WINDOW_MS) {
    return {count: 1, windowStart: now};
  }
  if (current.count >= limit) {
    throw rateLimited();
  }
  return {
    count: current.count + 1,
    windowStart: current.windowStart,
  };
}
