import {HttpsError} from "firebase-functions/v2/https";

export function unauthenticated(): HttpsError {
  return new HttpsError(
    "unauthenticated",
    "Authentication is required for this action.",
  );
}

export function rateLimited(): HttpsError {
  return new HttpsError(
    "resource-exhausted",
    "You're doing that a little too quickly. Please try again in a moment.",
  );
}

export function invalidArgument(message: string): HttpsError {
  return new HttpsError("invalid-argument", message);
}

export function failedPrecondition(message: string): HttpsError {
  return new HttpsError("failed-precondition", message);
}

export function notFound(message: string): HttpsError {
  return new HttpsError("not-found", message);
}

export function internal(message = "Unexpected server error."): HttpsError {
  return new HttpsError("internal", message);
}
