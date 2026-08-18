import {importPKCS8, SignJWT} from "jose";

import {ApiError, internal} from "./errors";

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
}

interface TokenCache {
  accessToken: string;
  expiresAt: number;
}

let tokenCache: TokenCache | null = null;

function parseServiceAccount(raw: string): ServiceAccount {
  const trimmed = raw.trim();
  if (!trimmed) {
    throw internal("Server is missing FIREBASE_SERVICE_ACCOUNT_JSON secret.");
  }
  try {
    const parsed = JSON.parse(trimmed) as ServiceAccount;
    if (!parsed.client_email || !parsed.private_key) {
      throw internal(
        "FIREBASE_SERVICE_ACCOUNT_JSON must include client_email and private_key.",
      );
    }
    // Google SA JSON uses "\n" escapes; reject obviously broken keys early.
    if (!parsed.private_key.includes("PRIVATE KEY")) {
      throw internal(
        "FIREBASE_SERVICE_ACCOUNT_JSON private_key looks invalid.",
      );
    }
    return parsed;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw internal(
      "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON. Re-upload the full service account key file.",
    );
  }
}

async function getAccessToken(serviceAccountJson: string): Promise<string> {
  const now = Date.now();
  if (tokenCache && tokenCache.expiresAt > now + 60_000) {
    return tokenCache.accessToken;
  }

  const sa = parseServiceAccount(serviceAccountJson);
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/datastore",
  })
    .setProtectedHeader({alg: "RS256", typ: "JWT"})
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {"Content-Type": "application/x-www-form-urlencoded"},
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!res.ok) {
    console.error("Google token exchange failed", await res.text());
    throw internal("Could not authenticate to Firestore.");
  }

  const data = (await res.json()) as {
    access_token?: string;
    expires_in?: number;
  };
  if (!data.access_token) {
    throw internal("Could not authenticate to Firestore.");
  }

  tokenCache = {
    accessToken: data.access_token,
    expiresAt: now + (data.expires_in ?? 3600) * 1000,
  };
  return data.access_token;
}

type FirestoreValue =
  | {nullValue: null}
  | {booleanValue: boolean}
  | {integerValue: string}
  | {doubleValue: number}
  | {stringValue: string}
  | {timestampValue: string}
  | {mapValue: {fields: Record<string, FirestoreValue>}};

function encodeFields(value: Record<string, unknown>): Record<string, FirestoreValue> {
  const fields: Record<string, FirestoreValue> = {};
  for (const [k, v] of Object.entries(value)) {
    if (v !== undefined) fields[k] = encodeValue(v);
  }
  return fields;
}

function encodeValue(value: unknown): FirestoreValue {
  if (value === null || value === undefined) return {nullValue: null};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "number") {
    if (Number.isInteger(value)) {
      return {integerValue: String(value)};
    }
    return {doubleValue: value};
  }
  if (value instanceof Date) {
    return {timestampValue: value.toISOString()};
  }
  if (typeof value === "object") {
    return {mapValue: {fields: encodeFields(value as Record<string, unknown>)}};
  }
  return {stringValue: String(value)};
}

function decodeValue(value: FirestoreValue | undefined): unknown {
  if (!value) return undefined;
  if ("nullValue" in value) return null;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("mapValue" in value) {
    const out: Record<string, unknown> = {};
    const fields = value.mapValue.fields ?? {};
    for (const [k, v] of Object.entries(fields)) {
      out[k] = decodeValue(v);
    }
    return out;
  }
  return undefined;
}

export class FirestoreClient {
  constructor(
    private readonly projectId: string,
    private readonly serviceAccountJson: string,
  ) {}

  private docPath(uid: string, ...parts: string[]): string {
    const base = `projects/${this.projectId}/databases/(default)/documents/users/${uid}`;
    return parts.length ? `${base}/${parts.join("/")}` : base;
  }

  private async authedFetch(url: string, init?: RequestInit): Promise<Response> {
    const token = await getAccessToken(this.serviceAccountJson);
    return fetch(url, {
      ...init,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        ...(init?.headers ?? {}),
      },
    });
  }

  async getUserDoc(uid: string): Promise<Record<string, unknown> | null> {
    const name = this.docPath(uid);
    const url = `https://firestore.googleapis.com/v1/${name}`;
    const res = await this.authedFetch(url);
    if (res.status === 404) return null;
    if (!res.ok) {
      console.error("Firestore get failed", await res.text());
      throw internal("Could not load budget data.");
    }
    const doc = (await res.json()) as {
      fields?: Record<string, FirestoreValue>;
    };
    return (decodeValue({mapValue: {fields: doc.fields ?? {}}}) ??
      {}) as Record<string, unknown>;
  }

  async getEntry(
    uid: string,
    category: string,
    entryId: string,
  ): Promise<Record<string, unknown> | null> {
    const name = this.docPath(uid, category, entryId);
    const url = `https://firestore.googleapis.com/v1/${name}`;
    const res = await this.authedFetch(url);
    if (res.status === 404) return null;
    if (!res.ok) {
      console.error("Firestore get entry failed", await res.text());
      throw internal("Could not load transaction.");
    }
    const doc = (await res.json()) as {
      fields?: Record<string, FirestoreValue>;
    };
    return (decodeValue({mapValue: {fields: doc.fields ?? {}}}) ??
      {}) as Record<string, unknown>;
  }

  /**
   * Atomically write budget (+ optional entry set/delete) via Commit API.
   */
  async commitUserBudget(options: {
    uid: string;
    budget: Record<string, unknown>;
    entry?: {
      category: string;
      entryId: string;
      data: Record<string, unknown>;
    };
    entries?: Array<{
      category: string;
      entryId: string;
      data: Record<string, unknown>;
    }>;
    deleteEntry?: {
      category: string;
      entryId: string;
    };
  }): Promise<void> {
    const writes: unknown[] = [];

    const userName = this.docPath(options.uid);
    const existing = await this.getUserDoc(options.uid);
    const merged = {...(existing ?? {}), budget: options.budget};

    writes.push({
      update: {
        name: userName,
        fields: encodeFields(merged),
      },
    });

    const entryWrites = [
      ...(options.entry ? [options.entry] : []),
      ...(options.entries ?? []),
    ];
    for (const entry of entryWrites) {
      const entryName = this.docPath(
        options.uid,
        entry.category,
        entry.entryId,
      );
      writes.push({
        update: {
          name: entryName,
          fields: encodeFields(entry.data),
        },
      });
    }

    if (options.deleteEntry) {
      writes.push({
        delete: this.docPath(
          options.uid,
          options.deleteEntry.category,
          options.deleteEntry.entryId,
        ),
      });
    }

    const url = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents:commit`;
    const res = await this.authedFetch(url, {
      method: "POST",
      body: JSON.stringify({writes}),
    });
    if (!res.ok) {
      console.error("Firestore commit failed", await res.text());
      throw internal("Could not save financial changes.");
    }
  }
}
