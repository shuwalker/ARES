import { useEffect, useMemo, useRef } from "react";
import { useLocation, useNavigate } from "@/lib/router";
import { useDomain } from "../context/CompanyContext";
import { toCompanyRelativePath } from "../lib/domain-routes";
import {
  getRememberedPathOwnerCompanyId,
  isRememberableCompanyPath,
  sanitizeRememberedPathForDomain,
} from "../lib/domain-page-memory";

const STORAGE_KEY = "paperclip.companyPaths";

function getCompanyPaths(): Record<string, string> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch {
    /* ignore */
  }
  return {};
}

function saveCompanyPath(companyId: string, path: string) {
  const paths = getCompanyPaths();
  paths[companyId] = path;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(paths));
}

/**
 * Remembers the last visited page per company and navigates to it on company switch.
 * Falls back to /dashboard if no page was previously visited for a company.
 */
export function useDomainPageMemory() {
  const { companies, selectedCompanyId, selectedDomain, selectionSource } = useDomain();
  const location = useLocation();
  const navigate = useNavigate();
  const prevCompanyId = useRef<string | null>(selectedCompanyId);
  const rememberedPathOwnerCompanyId = useMemo(
    () =>
      getRememberedPathOwnerCompanyId({
        companies,
        pathname: location.pathname,
        fallbackCompanyId: prevCompanyId.current,
      }),
    [companies, location.pathname],
  );

  // Save current path for current company on every location change.
  // Uses prevCompanyId ref so we save under the correct company even
  // during the render where selectedCompanyId has already changed.
  const fullPath = location.pathname + location.search;
  useEffect(() => {
    const companyId = rememberedPathOwnerCompanyId;
    const relativePath = toCompanyRelativePath(fullPath);
    if (companyId && isRememberableCompanyPath(relativePath)) {
      saveCompanyPath(companyId, relativePath);
    }
  }, [fullPath, rememberedPathOwnerCompanyId]);

  // Navigate to saved path when company changes
  useEffect(() => {
    if (!selectedCompanyId) return;

    if (
      prevCompanyId.current !== null &&
      selectedCompanyId !== prevCompanyId.current
    ) {
      if (selectionSource !== "route_sync" && selectedDomain) {
        const paths = getCompanyPaths();
        const targetPath = sanitizeRememberedPathForDomain({
          path: paths[selectedCompanyId],
          companyPrefix: selectedDomain.issuePrefix,
        });
        navigate(`/${selectedDomain.issuePrefix}${targetPath}`, { replace: true });
      }
    }
    prevCompanyId.current = selectedCompanyId;
  }, [selectedDomain, selectedCompanyId, selectionSource, navigate]);
}
