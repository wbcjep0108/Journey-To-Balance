import type {AuthUser} from "./auth";
import {badRequest, unauthorized} from "./errors";
import type {Env} from "./finance";
import {deleteFirebaseAuthUser, FirestoreClient} from "./firestore";

export interface DeleteAccountDependencies {
  purgeFirestoreUserTree(uid: string): Promise<void>;
  purgeWorkerState(uid: string): Promise<void>;
  deleteAuthAccount(uid: string): Promise<void>;
  now(): number;
}

export interface DeleteAccountOutcome {
  success: boolean;
  message: string;
}

/**
 * Irreversible user account deletion pipeline:
 * 1. Requires fresh reauthentication (auth_time within 5 minutes).
 * 2. Requires exact confirmation of registered email.
 * 3. Purges Firestore user document tree recursively (including unknown subcollections).
 * 4. Clears user's Worker Durable Object state (rate limits, idempotency).
 * 5. Deletes user identity from Firebase Authentication.
 */
export async function handleDeleteAccount(
  deps: DeleteAccountDependencies,
  user: AuthUser,
  body: {confirmationEmail?: unknown},
  maxAuthAgeSeconds = 300,
): Promise<DeleteAccountOutcome> {
  // 1. Fresh reauthentication check
  if (typeof user.authTime !== "number") {
    throw unauthorized(
      "Fresh authentication required. Please sign in again before deleting your account.",
    );
  }
  const nowSec = Math.floor(deps.now() / 1000);
  const ageSec = nowSec - user.authTime;
  if (ageSec > maxAuthAgeSeconds || user.authTime > nowSec + 60) {
    throw unauthorized(
      "Fresh authentication required. Please sign in again before deleting your account.",
    );
  }

  // 2. Exact registered email confirmation check
  if (!user.email || !user.email.trim()) {
    throw badRequest("Account does not have a valid registered email address.");
  }
  const confirmationEmail =
    typeof body.confirmationEmail === "string"
      ? body.confirmationEmail.trim().toLowerCase()
      : "";
  if (!confirmationEmail || confirmationEmail !== user.email.trim().toLowerCase()) {
    throw badRequest("Confirmation email does not match registered email.");
  }

  // 3. Purge Firestore data tree recursively
  await deps.purgeFirestoreUserTree(user.uid);

  // 4. Clear Durable Object state
  await deps.purgeWorkerState(user.uid);

  // 5. Delete Firebase Auth user
  await deps.deleteAuthAccount(user.uid);

  return {
    success: true,
    message: "Account and associated data have been permanently deleted.",
  };
}

export function createDeleteAccountDependencies(
  env: Env,
): DeleteAccountDependencies {
  const projectId = env.FIREBASE_PROJECT_ID || "journey-to-balance";
  const firestore = new FirestoreClient(
    projectId,
    env.FIREBASE_SERVICE_ACCOUNT_JSON,
  );

  return {
    async purgeFirestoreUserTree(uid: string): Promise<void> {
      await firestore.purgeUserTree(uid);
    },
    async purgeWorkerState(uid: string): Promise<void> {
      const gate = env.USER_GATE.get(env.USER_GATE.idFromName(uid));
      await gate.purgeUserData();
    },
    async deleteAuthAccount(uid: string): Promise<void> {
      await deleteFirebaseAuthUser(
        projectId,
        env.FIREBASE_SERVICE_ACCOUNT_JSON,
        uid,
      );
    },
    now: () => Date.now(),
  };
}

