import {getFirestore} from "firebase-admin/firestore";
import {CallableRequest} from "firebase-functions/v2/https";

import {unauthenticated} from "./errors.js";
import {
  nextRateBucket,
  RATE_LIMITS,
  RateBucketName,
  RateBucketState,
} from "./rateLimit.js";

export function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw unauthenticated();
  }
  return uid;
}

function rateLimitsRef(uid: string) {
  return getFirestore().collection("users").doc(uid)
    .collection("security").doc("rateLimits");
}

/**
 * Enforce the operation-specific limit and the general per-user limit.
 * Uses a Firestore transaction so concurrent requests share one window.
 */
export async function enforceRateLimits(
  uid: string,
  bucket: RateBucketName,
): Promise<void> {
  const ref = rateLimitsRef(uid);
  const now = Date.now();

  await getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = (snap.data() ?? {}) as Record<string, RateBucketState>;

    const nextOp = nextRateBucket(
      data[bucket],
      RATE_LIMITS[bucket],
      now,
    );
    const nextGeneral = nextRateBucket(
      data.general,
      RATE_LIMITS.general,
      now,
    );

    tx.set(ref, {
      [bucket]: nextOp,
      general: nextGeneral,
      updatedAt: now,
    }, {merge: true});
  });
}

export function idempotencyRef(uid: string, requestId: string) {
  return getFirestore().collection("users").doc(uid)
    .collection("security").doc("idempotency")
    .collection("requests").doc(requestId);
}
