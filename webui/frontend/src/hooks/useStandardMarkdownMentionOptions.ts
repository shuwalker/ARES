import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { agentsApi } from "../api/agents";
import { accessApi } from "../api/access";
import { projectsApi } from "../api/projects";
import { useDomain } from "../context/DomainContext";
import { buildMarkdownMentionOptions } from "../lib/domain-members";
import { queryKeys } from "../lib/queryKeys";

type MarkdownMentionInputs = Parameters<typeof buildMarkdownMentionOptions>[0];

type StandardMarkdownMentionOptionsArgs = {
  domainId?: string | null;
  enabled?: boolean;
} & Partial<MarkdownMentionInputs>;

export function useStandardMarkdownMentionOptions(args: StandardMarkdownMentionOptionsArgs = {}) {
  const { selectedDomainId } = useDomain();
  const domainId = args.domainId ?? selectedDomainId;
  const enabled = (args.enabled ?? true) && Boolean(domainId);

  const agentsQuery = useQuery({
    queryKey: domainId ? queryKeys.agents.list(domainId) : ["agents", "standard-mentions", "none"],
    queryFn: () => agentsApi.list(domainId!),
    enabled: enabled && args.agents === undefined,
  });
  const projectsQuery = useQuery({
    queryKey: domainId ? queryKeys.projects.list(domainId) : ["projects", "standard-mentions", "none"],
    queryFn: () => projectsApi.list(domainId!),
    enabled: enabled && args.projects === undefined,
  });
  const usersQuery = useQuery({
    queryKey: domainId ? queryKeys.access.domainUserDirectory(domainId) : ["access", "standard-mentions", "users", "none"],
    queryFn: () => accessApi.listUserDirectory(domainId!),
    enabled: enabled && args.members === undefined,
  });

  const agents = args.agents ?? agentsQuery.data;
  const projects = args.projects ?? projectsQuery.data;
  const members = args.members ?? usersQuery.data?.users;

  return useMemo(
    () => buildMarkdownMentionOptions({ agents, projects, members }),
    [agents, members, projects],
  );
}
