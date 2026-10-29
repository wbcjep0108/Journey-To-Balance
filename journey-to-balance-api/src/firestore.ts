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

const tokenCache = new Map<string, TokenCache>();

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

export async function getGoogleAccessToken(
  serviceAccountJson: string,
  scopes = ["https://www.googleapis.com/auth/datastore"],
): Promise<string> {
  const now = Date.now();
  const scope = [...scopes].sort().join(" ");
  const cached = tokenCache.get(scope);
  if (cached && cached.expiresAt > now + 60_000) {
    return cached.accessToken;
  }

  const sa = parseServiceAccount(serviceAccountJson);
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({
    scope,
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
    throw internal("Could not authenticate to Google services.");
  }

  const data = (await res.json()) as {
    access_token?: string;
    expires_in?: number;
  };
  if (!data.access_token) {
    throw internal("Could not authenticate to Google services.");
  }

  tokenCache.set(scope, {
    accessToken: data.access_token,
    expiresAt: now + (data.expires_in ?? 3600) * 1000,
  });
  return data.access_token;
}

/**
 * Permanently deletes a user identity from Firebase Authentication
 * via Google Identity Toolkit REST API using Service Account OAuth token.
 */
export async function deleteFirebaseAuthUser(
  projectId: string,
  serviceAccountJson: string,
  uid: string,
): Promise<void> {
  const token = await getGoogleAccessToken(serviceAccountJson, [
    "https://www.googleapis.com/auth/identitytoolkit",
  ]);
  const res = await fetch(
    "https://identitytoolkit.googleapis.com/v1/accounts:delete",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        localId: uid,
        targetProjectId: projectId,
      }),
    },
  );
  if (!res.ok && res.status !== 404) {
    const text = await res.text();
    console.error("Firebase Auth delete user failed", text);
    throw internal("Could not delete user account identity.");
  }
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
    const token = await getGoogleAccessToken(this.serviceAccountJson);
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

  async getSubDoc(
    uid: string,
    ...parts: string[]
  ): Promise<Record<string, unknown> | null> {
    const name = this.docPath(uid, ...parts);
    const url = `https://firestore.googleapis.com/v1/${name}`;
    const res = await this.authedFetch(url);
    if (res.status === 404) return null;
    if (!res.ok) {
      console.error("Firestore get subdoc failed", await res.text());
      throw internal("Could not load security data.");
    }
    const doc = (await res.json()) as {
      fields?: Record<string, FirestoreValue>;
    };
    return (decodeValue({mapValue: {fields: doc.fields ?? {}}}) ??
      {}) as Record<string, unknown>;
  }

  async setSubDoc(
    uid: string,
    parts: string[],
    data: Record<string, unknown>,
  ): Promise<void> {
    const name = this.docPath(uid, ...parts);
    const url = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents:commit`;
    const res = await this.authedFetch(url, {
      method: "POST",
      body: JSON.stringify({
        writes: [{update: {name, fields: encodeFields(data)}}],
      }),
    });
    if (!res.ok) {
      console.error("Firestore set subdoc failed", await res.text());
      throw internal("Could not save security data.");
    }
  }

  async deleteSubDoc(uid: string, ...parts: string[]): Promise<void> {
    const name = this.docPath(uid, ...parts);
    const url = `https://firestore.googleapis.com/v1/${name}`;
    const res = await this.authedFetch(url, {method: "DELETE"});
    if (res.status === 404) return;
    if (!res.ok) {
      console.error("Firestore delete subdoc failed", await res.text());
      throw internal("Could not update security data.");
    }
  }

  private async listSubcollectionIds(docPath: string): Promise<string[]> {
    const url = `https://firestore.googleapis.com/v1/${docPath}:listCollectionIds`;
    const res = await this.authedFetch(url, {
      method: "POST",
      body: JSON.stringify({pageSize: 100}),
    });
    if (res.status === 404) return [];
    if (!res.ok) {
      console.error("Firestore listCollectionIds failed", await res.text());
      return [];
    }
    const data = (await res.json()) as {collectionIds?: string[]};
    return data.collectionIds ?? [];
  }

  private async listDocumentsInCollection(
    parentPath: string,
    collectionId: string,
  ): Promise<string[]> {
    const docPaths: string[] = [];
    let pageToken: string | undefined;
    do {
      const query = new URLSearchParams({
        pageSize: "300",
        showMissing: "true",
      });
      if (pageToken) query.set("pageToken", pageToken);
      const url = `https://firestore.googleapis.com/v1/${parentPath}/${collectionId}?${query.toString()}`;
      const res = await this.authedFetch(url);
      if (res.status === 404) break;
      if (!res.ok) {
        console.error("Firestore list documents failed", await res.text());
        break;
      }
      const data = (await res.json()) as {
        documents?: Array<{name: string}>;
        nextPageToken?: string;
      };
      if (data.documents) {
        for (const doc of data.documents) {
          if (doc.name) docPaths.push(doc.name);
        }
      }
      pageToken = data.nextPageToken;
    } while (pageToken);
    return docPaths;
  }

  /**
   * Recursively deletes a document and all nested subcollections under it.
   */
  async recursivelyDeleteDocument(
    docPath: string,
    initialCollectionIds: string[] = [],
  ): Promise<void> {
    const discovered = await this.listSubcollectionIds(docPath);
    const allCollections = Array.from(
      new Set([...initialCollectionIds, ...discovered]),
    );

    for (const colId of allCollections) {
      const docNames = await this.listDocumentsInCollection(docPath, colId);
      for (const childDocName of docNames) {
        await this.recursivelyDeleteDocument(childDocName);
      }
    }

    const url = `https://firestore.googleapis.com/v1/${docPath}`;
    const res = await this.authedFetch(url, {method: "DELETE"});
    if (!res.ok && res.status !== 404) {
      console.error("Firestore delete doc failed", await res.text());
    }
  }

  /**
   * Purges the entire Firestore user document tree for the given UID,
   * including known subcollections and any dynamically discovered subcollections.
   */
  async purgeUserTree(uid: string): Promise<void> {
    const rootDocPath = this.docPath(uid);
    await this.recursivelyDeleteDocument(rootDocPath, [
      "bills",
      "savings",
      "personal",
      "wallet",
      "legal",
      "security",
      "pinReset",
    ]);
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
