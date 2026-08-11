import {DurableObject} from "cloudflare:workers";

import {ApiError, badRequest} from "./errors";
import {
  nextRateBucket,
  RATE_LIMITS,
  RateBucketName,
  RateBucketState,
  WINDOW_MS,
} from "./rateLimit";

interface IdempotencyRecord {
  result: unknown;
  createdAt: number;
}

const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000;

/**
 * Per-UID gate: rate limits + idempotency.
 * One Durable Object instance per Firebase UID (single-threaded → race-safe).
 * Uses SQLite-backed DO storage (Workers Free plan).
 */
export interface RateLimitResult {
  bucket: RateBucketName;
  limit: number;
  count: number;
  remaining: number;
  windowStart: number;
  resetAt: number;
}

/** Structured outcome — never throw ApiError across DO RPC (instanceof is lost). */
export type IsolatedRateLimitOutcome =
  | {ok: true; info: RateLimitResult}
  | {
    ok: false;
    info: RateLimitResult;
    code: string;
    message: string;
  };

export class UserGate extends DurableObject {
  /**
   * Production finance rate-limit path: increments op bucket + general.
   * Throws ApiError(429) when either limit is exceeded.
   */
  async enforceRateLimits(bucket: RateBucketName): Promise<void> {
    await this.applyFinanceRateLimits(bucket);
  }

  /**
   * Same counters/keys/limits as {@link enforceRateLimits}, but returns a
   * structured outcome so Worker HTTP can map 429 without DO RPC instanceof loss.
   *
   * Important: does NOT use try/catch + `instanceof ApiError` for the limit
   * check. Over-limit is detected from stored counts before any increment, so
   * a rejected request never mutates Firestore and never depends on error class
   * identity inside the DO isolate.
   */
  async enforceRateLimitsOutcome(
    bucket: RateBucketName,
  ): Promise<IsolatedRateLimitOutcome> {
    if (!(bucket in RATE_LIMITS)) {
      throw badRequest(`Unknown rate-limit bucket: ${bucket}`);
    }

    const now = Date.now();
    const opKey = `rate:${bucket}`;
    const generalKey = "rate:general";
    const limit = RATE_LIMITS[bucket];

    const opCurrent = await this.ctx.storage.get<RateBucketState>(opKey);
    const generalCurrent =
      await this.ctx.storage.get<RateBucketState>(generalKey);

    if (this.isBucketLimited(opCurrent, limit, now)) {
      return this.limitedOutcome(bucket, limit, opCurrent, now);
    }
    if (this.isBucketLimited(generalCurrent, RATE_LIMITS.general, now)) {
      return this.limitedOutcome(
        "general",
        RATE_LIMITS.general,
        generalCurrent,
        now,
      );
    }

    // Safe to increment — mirrors nextRateBucket without throw/instanceof.
    const nextOp = nextRateBucket(opCurrent, limit, now);
    const nextGeneral = nextRateBucket(
      generalCurrent,
      RATE_LIMITS.general,
      now,
    );

    await this.ctx.storage.put({
      [opKey]: nextOp,
      [generalKey]: nextGeneral,
    });

    return {
      ok: true,
      info: {
        bucket,
        limit,
        count: nextOp.count,
        remaining: Math.max(0, limit - nextOp.count),
        windowStart: nextOp.windowStart,
        resetAt: nextOp.windowStart + WINDOW_MS,
      },
    };
  }

  /** Shared production logic for op bucket + general (60/min). */
  private async applyFinanceRateLimits(
    bucket: RateBucketName,
  ): Promise<RateLimitResult> {
    const outcome = await this.enforceRateLimitsOutcome(bucket);
    if (!outcome.ok) {
      // Keep legacy throw path for any remaining callers of enforceRateLimits.
      throw new ApiError(429, outcome.code, outcome.message);
    }
    return outcome.info;
  }

  private isBucketLimited(
    current: RateBucketState | undefined,
    limit: number,
    now: number,
  ): boolean {
    if (!current || now - current.windowStart >= WINDOW_MS) {
      return false;
    }
    return current.count >= limit;
  }

  private limitedOutcome(
    bucket: RateBucketName,
    limit: number,
    current: RateBucketState | undefined,
    now: number,
  ): IsolatedRateLimitOutcome {
    const windowStart =
      current && now - current.windowStart < WINDOW_MS ?
        current.windowStart :
        now;
    return {
      ok: false,
      info: {
        bucket,
        limit,
        count: current?.count ?? limit,
        remaining: 0,
        windowStart,
        resetAt: windowStart + WINDOW_MS,
      },
      code: "rate-limit-exceeded",
      message:
        "You're doing that a little too quickly. Please try again in a moment.",
    };
  }

  /**
   * Isolated counter for non-mutating probes.
   * Only touches `rate:rateLimitTest` — never `general` or finance buckets.
   * Returns a result object instead of throwing across the DO RPC boundary.
   */
  async enforceIsolatedTestRateLimit(): Promise<IsolatedRateLimitOutcome> {
    const bucket = "rateLimitTest" as const;
    const limit = RATE_LIMITS[bucket];
    const now = Date.now();
    const opKey = `rate:${bucket}`;

    const opCurrent = await this.ctx.storage.get<RateBucketState>(opKey);
    try {
      const nextOp = nextRateBucket(opCurrent, limit, now);
      await this.ctx.storage.put(opKey, nextOp);
      return {
        ok: true,
        info: {
          bucket,
          limit,
          count: nextOp.count,
          remaining: Math.max(0, limit - nextOp.count),
          windowStart: nextOp.windowStart,
          resetAt: nextOp.windowStart + WINDOW_MS,
        },
      };
    } catch (error) {
      // Catch inside the DO isolate where ApiError identity is preserved.
      if (!(error instanceof ApiError) || error.status !== 429) {
        throw error;
      }
      const windowStart =
        opCurrent && now - opCurrent.windowStart < WINDOW_MS ?
          opCurrent.windowStart :
          now;
      return {
        ok: false,
        info: {
          bucket,
          limit,
          count: opCurrent?.count ?? limit,
          remaining: 0,
          windowStart,
          resetAt: windowStart + WINDOW_MS,
        },
        code: "rate-limit-exceeded",
        message:
          "You're doing that a little too quickly. Please try again in a moment.",
      };
    }
  }

  async getIdempotency(requestId: string): Promise<unknown | null> {
    const key = `idem:${requestId}`;
    const record = await this.ctx.storage.get<IdempotencyRecord>(key);
    if (!record) return null;
    if (Date.now() - record.createdAt > IDEMPOTENCY_TTL_MS) {
      await this.ctx.storage.delete(key);
      return null;
    }
    return record.result;
  }

  async saveIdempotency(requestId: string, result: unknown): Promise<void> {
    const key = `idem:${requestId}`;
    const record: IdempotencyRecord = {
      result,
      createdAt: Date.now(),
    };
    await this.ctx.storage.put(key, record);
  }
}
