export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export function unauthorized(message = "Authentication is required."): ApiError {
  return new ApiError(401, "unauthenticated", message);
}

export function forbidden(message = "Permission denied."): ApiError {
  return new ApiError(403, "permission-denied", message);
}

export function badRequest(message: string): ApiError {
  return new ApiError(400, "invalid-argument", message);
}

export function conflict(message: string): ApiError {
  return new ApiError(409, "failed-precondition", message);
}

export function notFound(message: string): ApiError {
  return new ApiError(404, "not-found", message);
}

export function rateLimited(): ApiError {
  return new ApiError(
    429,
    "resource-exhausted",
    "You're doing that a little too quickly. Please try again in a moment.",
  );
}

/** Thrown in the Worker isolate (not across DO RPC) so instanceof + headers work. */
export class RateLimitExceededError extends ApiError {
  constructor(
    readonly info: {
      bucket: string;
      limit: number;
      remaining: number;
      resetAt: number;
    },
    message =
      "You're doing that a little too quickly. Please try again in a moment.",
  ) {
    super(429, "rate-limit-exceeded", message);
    this.name = "RateLimitExceededError";
  }
}

export function internal(message = "Unexpected server error."): ApiError {
  return new ApiError(500, "internal", message);
}

export function jsonError(
  error: unknown,
  extraHeaders?: HeadersInit,
): Response {
  if (error instanceof ApiError) {
    const headers = new Headers(corsHeaders());
    if (extraHeaders) {
      new Headers(extraHeaders).forEach((value, key) => {
        headers.set(key, value);
      });
    }
    if (error instanceof RateLimitExceededError) {
      new Headers(
        rateLimitHeaders({
          bucket: error.info.bucket,
          limit: error.info.limit,
          remaining: error.info.remaining,
          resetAt: error.info.resetAt,
        }),
      ).forEach((value, key) => {
        headers.set(key, value);
      });
      const retryAfterSec = Math.max(
        1,
        Math.ceil((error.info.resetAt - Date.now()) / 1000),
      );
      headers.set("Retry-After", String(retryAfterSec));
    } else if (error.status === 429 && !headers.has("Retry-After")) {
      headers.set("Retry-After", "60");
    }
    return Response.json(
      {error: {code: error.code, message: error.message}},
      {
        status: error.status,
        headers,
      },
    );
  }
  console.error(error);
  return Response.json(
    {error: {code: "internal", message: "Unexpected server error."}},
    {status: 500, headers: corsHeaders()},
  );
}

export function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Expose-Headers":
      "Retry-After, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset, X-RateLimit-Bucket",
  };
}

export function jsonOk(
  body: unknown,
  status = 200,
  extraHeaders?: HeadersInit,
): Response {
  const headers = new Headers(corsHeaders());
  if (extraHeaders) {
    new Headers(extraHeaders).forEach((value, key) => {
      headers.set(key, value);
    });
  }
  return Response.json(body, {status, headers});
}

export function rateLimitHeaders(info: {
  bucket: string;
  limit: number;
  remaining: number;
  resetAt: number;
}): HeadersInit {
  return {
    "X-RateLimit-Limit": String(info.limit),
    "X-RateLimit-Remaining": String(info.remaining),
    "X-RateLimit-Reset": String(Math.ceil(info.resetAt / 1000)),
    "X-RateLimit-Bucket": info.bucket,
  };
}
