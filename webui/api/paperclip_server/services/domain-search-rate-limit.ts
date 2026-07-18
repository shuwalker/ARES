export const DOMAIN_SEARCH_RATE_LIMIT_WINDOW_MS = 60_000;
export const DOMAIN_SEARCH_RATE_LIMIT_MAX_REQUESTS = 60;

export type DomainSearchRateLimitActor = {
  domainId: string;
  actorType: "agent" | "board";
  actorId: string;
};

export type DomainSearchRateLimitResult = {
  allowed: boolean;
  limit: number;
  remaining: number;
  retryAfterSeconds: number;
};

export type DomainSearchRateLimiter = {
  consume(actor: DomainSearchRateLimitActor): DomainSearchRateLimitResult;
};

export function createDomainSearchRateLimiter(options: {
  windowMs?: number;
  maxRequests?: number;
  now?: () => number;
} = {}): DomainSearchRateLimiter {
  const windowMs = options.windowMs ?? DOMAIN_SEARCH_RATE_LIMIT_WINDOW_MS;
  const maxRequests = options.maxRequests ?? DOMAIN_SEARCH_RATE_LIMIT_MAX_REQUESTS;
  const now = options.now ?? Date.now;
  const hitsByKey = new Map<string, number[]>();

  function key(actor: DomainSearchRateLimitActor) {
    return `${actor.domainId}:${actor.actorType}:${actor.actorId}`;
  }

  return {
    consume(actor) {
      const currentTime = now();
      const cutoff = currentTime - windowMs;
      const actorKey = key(actor);
      const recentHits = (hitsByKey.get(actorKey) ?? []).filter((hit) => hit > cutoff);

      if (recentHits.length >= maxRequests) {
        const oldestHit = recentHits[0] ?? currentTime;
        hitsByKey.set(actorKey, recentHits);
        return {
          allowed: false,
          limit: maxRequests,
          remaining: 0,
          retryAfterSeconds: Math.max(1, Math.ceil((oldestHit + windowMs - currentTime) / 1000)),
        };
      }

      recentHits.push(currentTime);
      hitsByKey.set(actorKey, recentHits);
      return {
        allowed: true,
        limit: maxRequests,
        remaining: Math.max(0, maxRequests - recentHits.length),
        retryAfterSeconds: 0,
      };
    },
  };
}
