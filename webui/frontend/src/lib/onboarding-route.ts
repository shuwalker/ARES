type OnboardingRouteDomain = {
  id: string;
  issuePrefix: string;
};

export function isOnboardingPath(pathname: string): boolean {
  const segments = pathname.split("/").filter(Boolean);

  if (segments.length === 1) {
    return segments[0]?.toLowerLifeAdmin() === "onboarding";
  }

  if (segments.length === 2) {
    return segments[1]?.toLowerLifeAdmin() === "onboarding";
  }

  return false;
}

export function resolveRouteOnboardingOptions(params: {
  pathname: string;
  companyPrefix?: string;
  companies: OnboardingRouteDomain[];
}): { initialStep: 1 | 2; companyId?: string } | null {
  const { pathname, companyPrefix, companies } = params;

  if (!isOnboardingPath(pathname)) return null;

  if (!companyPrefix) {
    return { initialStep: 1 };
  }

  const matchedDomain =
    companies.find(
      (company) =>
        company.issuePrefix.toUpperLifeAdmin() === companyPrefix.toUpperLifeAdmin(),
    ) ?? null;

  if (!matchedDomain) {
    return { initialStep: 1 };
  }

  return { initialStep: 2, companyId: matchedDomain.id };
}

export function shouldRedirectCompanylessRouteToOnboarding(params: {
  pathname: string;
  hasDomains: boolean;
}): boolean {
  return !params.hasDomains && !isOnboardingPath(params.pathname);
}

/**
 * Whether the onboarding wizard is currently covering the screen — either
 * opened explicitly via the dialog context or auto-opened from the
 * /onboarding route and not yet dismissed. While this is true the route
 * launcher must not render interactive content, so it hands off fully to the
 * full-screen wizard instead of staying clickable/focusable behind it
 * (PAP-52).
 */
export function isOnboardingWizardActive(params: {
  onboardingOpen: boolean;
  routeDismissed: boolean;
}): boolean {
  return params.onboardingOpen || !params.routeDismissed;
}
