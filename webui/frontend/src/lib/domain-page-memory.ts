import {
  extractDomainPrefixFromPath,
  normalizeDomainPrefix,
  toDomainRelativePath,
} from "./domain-routes";

const GLOBAL_SEGMENTS = new Set(["auth", "invite", "board-claim", "cli-auth", "docs"]);

export function isRememberableDomainPath(path: string): boolean {
  const pathname = path.split("?")[0] ?? "";
  const segments = pathname.split("/").filter(Boolean);
  if (segments.length === 0) return true;
  const [root] = segments;
  if (GLOBAL_SEGMENTS.has(root!)) return false;
  return true;
}

function findDomainByPrefix<T extends { id: string; issuePrefix: string }>(params: {
  domains: T[];
  domainPrefix: string;
}): T | null {
  const normalizedPrefix = normalizeDomainPrefix(params.domainPrefix);
  return params.domains.find((domain) => normalizeDomainPrefix(domain.issuePrefix) === normalizedPrefix) ?? null;
}

export function getRememberedPathOwnerDomainId<T extends { id: string; issuePrefix: string }>(params: {
  domains: T[];
  pathname: string;
  fallbackDomainId: string | null;
}): string | null {
  const routeDomainPrefix = extractDomainPrefixFromPath(params.pathname);
  if (!routeDomainPrefix) {
    return params.fallbackDomainId;
  }

  return findDomainByPrefix({
    domains: params.domains,
    domainPrefix: routeDomainPrefix,
  })?.id ?? null;
}

export function sanitizeRememberedPathForDomain(params: {
  path: string | null | undefined;
  domainPrefix: string;
}): string {
  const relativePath = params.path ? toDomainRelativePath(params.path) : "/dashboard";
  if (!isRememberableDomainPath(relativePath)) {
    return "/dashboard";
  }

  const pathname = relativePath.split("?")[0] ?? "";
  const segments = pathname.split("/").filter(Boolean);
  const [root, entityId] = segments;
  if (root === "issues" && entityId) {
    const identifierMatch = /^([A-Za-z]+)-\d+$/.exec(entityId);
    if (
      identifierMatch &&
      normalizeDomainPrefix(identifierMatch[1] ?? "") !== normalizeDomainPrefix(params.domainPrefix)
    ) {
      return "/dashboard";
    }
  }

  return relativePath;
}
