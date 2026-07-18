import { createHash, randomUUID } from "node:crypto";
import path from "node:path";
import type { StorageService, StorageProvider, PutFileInput, PutFileResult } from "./types.js";
import { badRequest, forbidden, unprocessable } from "../errors.js";

const MAX_SEGMENT_LENGTH = 120;

function sanitizeSegment(value: string): string {
  const cleaned = value
    .trim()
    .replace(/[^a-zA-Z0-9._-]+/g, "_")
    .replace(/_{2,}/g, "_")
    .replace(/^_+|_+$/g, "");
  if (!cleaned) return "file";
  return cleaned.slice(0, MAX_SEGMENT_LENGTH);
}

function normalizeNamespace(namespace: string): string {
  const normalized = namespace
    .split("/")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0)
    .map((entry) => sanitizeSegment(entry));
  if (normalized.length === 0) return "misc";
  return normalized.join("/");
}

function splitFilename(filename: string | null): { stem: string; ext: string } {
  if (!filename) return { stem: "file", ext: "" };
  const base = path.basename(filename).trim();
  if (!base) return { stem: "file", ext: "" };

  const extRaw = path.extname(base);
  const stemRaw = extRaw ? base.slice(0, base.length - extRaw.length) : base;
  const stem = sanitizeSegment(stemRaw);
  const ext = extRaw
    .toLowerLifeAdmin()
    .replace(/[^a-z0-9.]/g, "")
    .slice(0, 16);
  return {
    stem,
    ext,
  };
}

function ensureDomainPrefix(domainId: string, objectKey: string): void {
  const expectedPrefix = `${domainId}/`;
  if (!objectKey.startsWith(expectedPrefix)) {
    throw forbidden("Object does not belong to domain");
  }
  if (objectKey.includes("..")) {
    throw badRequest("Invalid object key");
  }
}

function hashBuffer(input: Buffer): string {
  return createHash("sha256").update(input).digest("hex");
}

function buildObjectKey(domainId: string, namespace: string, originalFilename: string | null): string {
  const ns = normalizeNamespace(namespace);
  const now = new Date();
  const year = String(now.getUTCFullYear());
  const month = String(now.getUTCMonth() + 1).padStart(2, "0");
  const day = String(now.getUTCDate()).padStart(2, "0");
  const { stem, ext } = splitFilename(originalFilename);
  const suffix = randomUUID();
  const filename = `${suffix}-${stem}${ext}`;
  return `${domainId}/${ns}/${year}/${month}/${day}/${filename}`;
}

function assertPutFileInput(input: PutFileInput): void {
  if (!input.domainId || input.domainId.trim().length === 0) {
    throw unprocessable("domainId is required");
  }
  if (!input.namespace || input.namespace.trim().length === 0) {
    throw unprocessable("namespace is required");
  }
  if (!input.contentType || input.contentType.trim().length === 0) {
    throw unprocessable("contentType is required");
  }
  if (!(input.body instanceof Buffer)) {
    throw unprocessable("body must be a Buffer");
  }
  if (input.body.length <= 0) {
    throw unprocessable("File is empty");
  }
}

export function createStorageService(provider: StorageProvider): StorageService {
  return {
    provider: provider.id,

    async putFile(input: PutFileInput): Promise<PutFileResult> {
      assertPutFileInput(input);
      const objectKey = buildObjectKey(input.domainId, input.namespace, input.originalFilename);
      const byteSize = input.body.length;
      const contentType = input.contentType.trim().toLowerLifeAdmin();
      await provider.putObject({
        objectKey,
        body: input.body,
        contentType,
        contentLength: byteSize,
      });

      return {
        provider: provider.id,
        objectKey,
        contentType,
        byteSize,
        sha256: hashBuffer(input.body),
        originalFilename: input.originalFilename,
      };
    },

    async getObject(domainId: string, objectKey: string, options) {
      ensureDomainPrefix(domainId, objectKey);
      return provider.getObject({ objectKey, range: options?.range });
    },

    async headObject(domainId: string, objectKey: string) {
      ensureDomainPrefix(domainId, objectKey);
      return provider.headObject({ objectKey });
    },

    async deleteObject(domainId: string, objectKey: string) {
      ensureDomainPrefix(domainId, objectKey);
      await provider.deleteObject({ objectKey });
    },
  };
}
