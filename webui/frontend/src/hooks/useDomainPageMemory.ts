import { useEffect, useMemo, useRef } from "react";
import { useLocation, useNavigate } from "@/lib/router";
import { useDomain } from "../context/DomainContext";
import { toDomainRelativePath } from "../lib/domain-routes";
import {
  getRememberedPathOwnerDomainId,
  isRememberableDomainPath,
  sanitizeRememberedPathForDomain,
} from "../lib/domain-page-memory";

const STORAGE_KEY = "ares.domainPaths";

function getDomainPaths(): Record<string, string> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {
    /* ignore */
  }
  return {};
}

function saveDomainPath(domainId: string, path: string) {
  const paths = getDomainPaths();
  paths[domainId] = path;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(paths));
}

/**
 * Remembers the last visited page per domain and navigates to it on domain switch.
 * Falls back to /dashboard if no page was previously visited for a domain.
 */
export function useDomainPageMemory() {
  const { domains, selectedDomainId, selectedDomain, selectionSource } = useDomain();
  const location = useLocation();
  const navigate = useNavigate();
  const prevDomainId = useRef<string | null>(selectedDomainId);
  const rememberedPathOwnerDomainId = useMemo(
    () =>
      getRememberedPathOwnerDomainId({
        domains,
        pathname: location.pathname,
        fallbackDomainId: prevDomainId.current,
      }),
    [domains, location.pathname],
  );

  // Save current path for current domain on every location change.
  // Uses prevDomainId ref so we save under the correct domain even
  // during the render where selectedDomainId has already changed.
  const fullPath = location.pathname + location.search;
  useEffect(() => {
    const domainId = rememberedPathOwnerDomainId;
    const relativePath = toDomainRelativePath(fullPath);
    if (domainId && isRememberableDomainPath(relativePath)) {
      saveDomainPath(domainId, relativePath);
    }
  }, [fullPath, rememberedPathOwnerDomainId]);

  // Navigate to saved path when domain changes
  useEffect(() => {
    if (!selectedDomainId) return;

    if (
      prevDomainId.current !== null &&
      selectedDomainId !== prevDomainId.current
    ) {
      if (selectionSource !== "route_sync" && selectedDomain) {
        const paths = getDomainPaths();
        const targetPath = sanitizeRememberedPathForDomain({
          path: paths[selectedDomainId],
          domainPrefix: selectedDomain.issuePrefix,
        });
        navigate(`/${selectedDomain.issuePrefix}${targetPath}`, { replace: true });
      }
    }
    prevDomainId.current = selectedDomainId;
  }, [selectedDomain, selectedDomainId, selectionSource, navigate]);
}
