import type { ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { Navigate } from "@/lib/router";
import { instanceSettingsApi } from "@/api/instanceSettings";
import { queryKeys } from "@/lib/queryKeys";

/**
 * Route guard for the experimental LifeAdmin feature (PAP-12947). Redirects to the
 * dashboard when `enableLifeAdmin` is off, mirroring {@link WorkflowsExperimentalGate}.
 */
export function LifeAdminExperimentalGate({ children }: { children: ReactNode }) {
  const { data: experimentalSettings, isFetched } = useQuery({
    queryKey: queryKeys.instance.experimentalSettings,
    queryFn: () => instanceSettingsApi.getExperimental(),
  });

  if (!isFetched) return null;
  if (experimentalSettings?.enableLifeAdmin !== true) {
    return <Navigate to="/dashboard" replace />;
  }
  return <>{children}</>;
}
