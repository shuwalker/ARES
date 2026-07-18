import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type {
  ResourceMembershipResourceType,
  ResourceMembershipState,
  ResourceMemberships,
} from "@paperclipai/shared";
import { resourceMembershipsApi } from "../api/resourceMemberships";
import { useToastActions } from "../context/ToastContext";
import { queryKeys } from "../lib/queryKeys";

type MutationVariables = {
  resourceType: ResourceMembershipResourceType;
  resourceId: string;
  resourceName: string;
  /** Join / leave transition. Omit to only change the starred flag. */
  state?: ResourceMembershipState;
  /** Star / unstar transition. Omit to only change join/leave state. */
  starred?: boolean;
};

function emptyMemberships(): ResourceMemberships {
  return {
    projectMemberships: {},
    agentMemberships: {},
    starredProjectIds: [],
    starredAgentIds: [],
    projectStarredAt: {},
    agentStarredAt: {},
    updatedAt: null,
  };
}

function starKeys(resourceType: ResourceMembershipResourceType) {
  return resourceType === "project"
    ? { ids: "starredProjectIds", at: "projectStarredAt", state: "projectMemberships" }
    : { ids: "starredAgentIds", at: "agentStarredAt", state: "agentMemberships" };
}

/**
 * Apply an optimistic membership change to the cached memberships snapshot.
 * Mirrors the server rules (see server/src/services/resource-memberships.ts):
 *   - starred=true always implies joined and stamps starredAt,
 *   - starred=false clears the star but leaves join/leave state alone,
 *   - state="left" clears any star (you cannot star a left resource).
 */
function applyMembershipChange(
  current: ResourceMemberships | undefined,
  resourceType: ResourceMembershipResourceType,
  resourceId: string,
  change: { state?: ResourceMembershipState; starred?: boolean },
): ResourceMemberships {
  const base = current ?? emptyMemberships();
  const keys = starKeys(resourceType);

  // Resolve next join/leave state (starring implies joined).
  const currentStateMap = base[keys.state as "projectMemberships"] ?? {};
  const previousState: ResourceMembershipState =
    currentStateMap[resourceId] === "left" ? "left" : "joined";
  const nextState: ResourceMembershipState =
    change.starred === true ? "joined" : change.state ?? previousState;

  // Resolve next starred set.
  const currentStarredIds = base[keys.ids as "starredProjectIds"] ?? [];
  const nextStarredAt = { ...(base[keys.at as "projectStarredAt"] ?? {}) };
  const previouslyStarred = currentStarredIds.includes(resourceId);
  const nextStarred =
    nextState === "left"
      ? false
      : change.starred === true
        ? true
        : change.starred === false
          ? false
          : previouslyStarred;

  let starredIds = currentStarredIds;
  if (nextStarred && !previouslyStarred) {
    // Newest star sorts first, matching the server's starredAt DESC ordering.
    starredIds = [resourceId, ...currentStarredIds];
    nextStarredAt[resourceId] = new Date();
  } else if (!nextStarred && previouslyStarred) {
    starredIds = currentStarredIds.filter((id) => id !== resourceId);
    delete nextStarredAt[resourceId];
  }

  return {
    ...base,
    [keys.state]: {
      ...currentStateMap,
      [resourceId]: nextState,
    },
    [keys.ids]: starredIds,
    [keys.at]: nextStarredAt,
    updatedAt: new Date(),
  };
}

export function resourceMembershipState(
  memberships: ResourceMemberships | undefined,
  resourceType: ResourceMembershipResourceType,
  resourceId: string,
): ResourceMembershipState {
  const state = resourceType === "project"
    ? memberships?.projectMemberships[resourceId]
    : memberships?.agentMemberships[resourceId];
  return state === "left" ? "left" : "joined";
}

/** Whether the current viewer has starred this resource (navigation preference). */
export function isStarred(
  memberships: ResourceMemberships | undefined,
  resourceType: ResourceMembershipResourceType,
  resourceId: string,
): boolean {
  const ids = resourceType === "project"
    ? memberships?.starredProjectIds
    : memberships?.starredAgentIds;
  return Array.isArray(ids) && ids.includes(resourceId);
}

/** Ordered starred ids (server returns starredAt DESC; falls back to empty). */
export function starredResourceIds(
  memberships: ResourceMemberships | undefined,
  resourceType: ResourceMembershipResourceType,
): string[] {
  const ids = resourceType === "project"
    ? memberships?.starredProjectIds
    : memberships?.starredAgentIds;
  return Array.isArray(ids) ? ids : [];
}

export function useResourceMemberships(domainId: string | null | undefined) {
  return useQuery({
    queryKey: queryKeys.resourceMemberships.mine(domainId ?? "__none__"),
    queryFn: () => resourceMembershipsApi.listMine(domainId!),
    enabled: !!domainId,
  });
}

export function useResourceMembershipMutation(domainId: string | null | undefined) {
  const queryClient = useQueryClient();
  const { pushToast } = useToastActions();
  const queryKey = queryKeys.resourceMemberships.mine(domainId ?? "__none__");

  return useMutation({
    mutationFn: (variables: MutationVariables) => {
      if (!domainId) throw new Error("Select a domain first.");
      const body = { state: variables.state, starred: variables.starred };
      return variables.resourceType === "project"
        ? resourceMembershipsApi.updateProject(domainId, variables.resourceId, body)
        : resourceMembershipsApi.updateAgent(domainId, variables.resourceId, body);
    },
    onMutate: async (variables) => {
      await queryClient.cancelQueries({ queryKey });
      const previous = queryClient.getQueryData<ResourceMemberships>(queryKey);
      queryClient.setQueryData<ResourceMemberships>(
        queryKey,
        applyMembershipChange(previous, variables.resourceType, variables.resourceId, {
          state: variables.state,
          starred: variables.starred,
        }),
      );
      return { previous };
    },
    onError: (error, variables, context) => {
      if (context?.previous) {
        queryClient.setQueryData(queryKey, context.previous);
      }
      const verb = variables.starred !== undefined
        ? variables.starred ? "star" : "unstar"
        : variables.state === "left" ? "leave" : "join";
      pushToast({
        title: `Couldn't ${verb} ${variables.resourceName}.`,
        body: error instanceof Error ? error.message : "Try again.",
        tone: "error",
      });
    },
    onSuccess: (result, variables) => {
      queryClient.setQueryData<ResourceMemberships>(
        queryKey,
        // Loose null-check: a missing or null starredAt both mean "not starred".
        (current) => applyMembershipChange(current, variables.resourceType, result.resourceId, {
          state: result.state,
          starred: result.starredAt != null,
        }),
      );
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey });
    },
  });
}
