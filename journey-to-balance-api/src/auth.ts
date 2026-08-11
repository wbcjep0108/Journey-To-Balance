import {createRemoteJWKSet, jwtVerify} from "jose";

import {unauthorized} from "./errors";

const JWKS = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

export interface AuthUser {
  uid: string;
  email?: string;
}

/**
 * Verify a Firebase ID token from Authorization: Bearer <token>.
 * UID always comes from the verified token `sub` claim — never from the body.
 */
export async function verifyFirebaseIdToken(
  request: Request,
  projectId: string,
): Promise<AuthUser> {
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) {
    throw unauthorized("Missing Authorization Bearer token.");
  }

  const token = match[1].trim();
  if (!token) {
    throw unauthorized("Missing Authorization Bearer token.");
  }

  try {
    const {payload} = await jwtVerify(token, JWKS, {
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
    });

    const uid = typeof payload.sub === "string" ? payload.sub : "";
    if (!uid) {
      throw unauthorized("Invalid Firebase ID token.");
    }

    return {
      uid,
      email: typeof payload.email === "string" ? payload.email : undefined,
    };
  } catch (error) {
    if (error instanceof Error && error.name === "ApiError") throw error;
    throw unauthorized("Invalid or expired Firebase ID token.");
  }
}
