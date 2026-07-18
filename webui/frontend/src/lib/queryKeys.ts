export const queryKeys = {
  domains: {
    all: ["domains"] as const,
    detail: (id: string) => ["domains", id] as const,
    stats: ["domains", "stats"] as const,
  },
  domainSkills: {
    list: (domainId: string) => ["domain-skills", domainId] as const,
    listRecent: (domainId: string) =>
      ["domain-skills", domainId, "recent-updated"] as const,
    detail: (domainId: string, skillId: string) => ["domain-skills", domainId, skillId] as const,
    versions: (domainId: string, skillId: string) => ["domain-skills", domainId, skillId, "versions"] as const,
    comments: (domainId: string, skillId: string) => ["domain-skills", domainId, skillId, "comments"] as const,
    updateStatus: (domainId: string, skillId: string) =>
      ["domain-skills", domainId, skillId, "update-status"] as const,
    forkPrecheck: (domainId: string, skillId: string) =>
      ["domain-skills", domainId, skillId, "fork-precheck"] as const,
    file: (domainId: string, skillId: string, relativePath: string) =>
      ["domain-skills", domainId, skillId, "file", relativePath] as const,
    catalog: (filters: { kind?: string; category?: string; q?: string } = {}) =>
      ["domain-skills", "catalog", filters.kind ?? "__all-kinds__", filters.category ?? "__all-categories__", filters.q ?? ""] as const,
    catalogDetail: (catalogRef: string) => ["domain-skills", "catalog", "detail", catalogRef] as const,
    catalogFile: (catalogRef: string, relativePath: string) =>
      ["domain-skills", "catalog", "file", catalogRef, relativePath] as const,
    testInputs: (domainId: string, skillId: string) =>
      ["domain-skills", domainId, skillId, "test-inputs"] as const,
    testRunTemplates: (domainId: string) =>
      ["domain-skills", domainId, "test-run-templates"] as const,
    testRuns: (domainId: string, skillId: string, inputId?: string | null) =>
      ["domain-skills", domainId, skillId, "test-runs", inputId ?? "__all-inputs__"] as const,
    testRunDetail: (domainId: string, skillId: string, runId: string) =>
      ["domain-skills", domainId, skillId, "test-run", runId] as const,
  },
  teamCatalog: {
    catalog: (filters: { kind?: string; category?: string; q?: string } = {}) =>
      ["team-catalog", "catalog", filters.kind ?? "__all-kinds__", filters.category ?? "__all-categories__", filters.q ?? ""] as const,
    catalogDetail: (catalogRef: string) => ["team-catalog", "catalog", "detail", catalogRef] as const,
    catalogFile: (catalogRef: string, relativePath: string) =>
      ["team-catalog", "catalog", "file", catalogRef, relativePath] as const,
    installed: (domainId: string) => ["team-catalog", "installed", domainId] as const,
  },
  agents: {
    list: (domainId: string) => ["agents", domainId] as const,
    detail: (id: string) => ["agents", "detail", id] as const,
    runtimeState: (id: string) => ["agents", "runtime-state", id] as const,
    taskSessions: (id: string) => ["agents", "task-sessions", id] as const,
    skills: (id: string) => ["agents", "skills", id] as const,
    instructionsBundle: (id: string) => ["agents", "instructions-bundle", id] as const,
    instructionsFile: (id: string, relativePath: string) =>
      ["agents", "instructions-bundle", id, "file", relativePath] as const,
    keys: (agentId: string) => ["agents", "keys", agentId] as const,
    configRevisions: (agentId: string) => ["agents", "config-revisions", agentId] as const,
    adapterModels: (domainId: string, adapterType: string, environmentId?: string | null) =>
      ["agents", domainId, "adapter-models", adapterType, environmentId ?? null] as const,
    adapterModelProfiles: (domainId: string, adapterType: string) =>
      ["agents", domainId, "adapter-model-profiles", adapterType] as const,
    detectModel: (domainId: string, adapterType: string) =>
      ["agents", domainId, "detect-model", adapterType] as const,
  },
  builtInAgents: {
    list: (domainId: string) => ["built-in-agents", domainId] as const,
  },
  issues: {
    list: (domainId: string) => ["issues", domainId] as const,
    mentionPool: (domainId: string) => ["issues", domainId, "mention-pool"] as const,
    search: (domainId: string, q: string, projectId?: string, limit?: number) =>
      ["issues", domainId, "search", q, projectId ?? "__all-projects__", limit ?? "__no-limit__"] as const,
    listAssignedToMe: (domainId: string) => ["issues", domainId, "assigned-to-me"] as const,
    listMineByMe: (domainId: string) => ["issues", domainId, "mine-by-me"] as const,
    listTouchedByMe: (domainId: string) => ["issues", domainId, "touched-by-me"] as const,
    listUnreadTouchedByMe: (domainId: string) => ["issues", domainId, "unread-touched-by-me"] as const,
    listBlockedAttention: (domainId: string) => ["issues", domainId, "blocked-attention"] as const,
    countBlockedAttention: (domainId: string) => ["issues", domainId, "blocked-attention", "count"] as const,
    labels: (domainId: string) => ["issues", domainId, "labels"] as const,
    listByProject: (domainId: string, projectId: string) =>
      ["issues", domainId, "project", projectId] as const,
    listPluginOperationsByProject: (domainId: string, projectId: string, originKindPrefix: string) =>
      ["issues", domainId, "project", projectId, "plugin-operations", originKindPrefix] as const,
    listByParent: (domainId: string, parentId: string) =>
      ["issues", domainId, "parent", parentId] as const,
    listByDescendantRoot: (domainId: string, rootIssueId: string) =>
      ["issues", domainId, "descendants", rootIssueId] as const,
    listByExecutionWorkspace: (domainId: string, executionWorkspaceId: string) =>
      ["issues", domainId, "execution-workspace", executionWorkspaceId] as const,
    detail: (id: string) => ["issues", "detail", id] as const,
    comments: (issueId: string) => ["issues", "comments", issueId] as const,
    commentsList: (issueId: string) => ["issues", "comments", issueId, "list"] as const,
    interactions: (issueId: string) => ["issues", "interactions", issueId] as const,
    acceptedPlanDecompositions: (issueId: string) =>
      ["issues", "accepted-plan-decompositions", issueId] as const,
    feedbackVotes: (issueId: string) => ["issues", "feedback-votes", issueId] as const,
    financeSummary: (issueId: string, options: { excludeRoot?: boolean } = {}) =>
      options.excludeRoot
        ? (["issues", "finance-summary", issueId, "exclude-root"] as const)
        : (["issues", "finance-summary", issueId] as const),
    attachments: (issueId: string) => ["issues", "attachments", issueId] as const,
    attachmentPreview: (attachmentId: string) => ["issues", "attachment-preview", attachmentId] as const,
    documents: (issueId: string) => ["issues", "documents", issueId] as const,
    document: (issueId: string, key: string) => ["issues", "document", issueId, key] as const,
    documentRevisions: (issueId: string, key: string) => ["issues", "document-revisions", issueId, key] as const,
    documentAnnotations: (issueId: string, key: string, status: "open" | "resolved" | "all" = "all") =>
      ["issues", "document-annotations", issueId, key, status] as const,
    activity: (issueId: string) => ["issues", "activity", issueId] as const,
    runs: (issueId: string) => ["issues", "runs", issueId] as const,
    approvals: (issueId: string) => ["issues", "approvals", issueId] as const,
    liveRuns: (issueId: string) => ["issues", "live-runs", issueId] as const,
    activeRun: (issueId: string) => ["issues", "active-run", issueId] as const,
    workProducts: (issueId: string) => ["issues", "work-products", issueId] as const,
    fileResources: (
      issueId: string,
      options: {
        workspace?: string;
        projectId?: string | null;
        workspaceId?: string | null;
        path?: string | null;
        mode?: string;
        q?: string | null;
        limit?: number;
        offset?: number;
      } = {},
    ) =>
      ["issues", "file-resources", issueId, "list", options] as const,
    fileResource: (
      issueId: string,
      query: { path: string; workspace?: string; projectId?: string | null; workspaceId?: string | null },
    ) =>
      ["issues", "file-resources", issueId, "resolve", query] as const,
    fileResourceContent: (
      issueId: string,
      query: { path: string; workspace?: string; projectId?: string | null; workspaceId?: string | null },
    ) =>
      ["issues", "file-resources", issueId, "content", query] as const,
  },
  routines: {
    list: (domainId: string, filters?: { projectId?: string | null }) =>
      ["routines", domainId, filters?.projectId ?? "__all-projects__"] as const,
    detail: (id: string) => ["routines", "detail", id] as const,
    runs: (id: string) => ["routines", "runs", id] as const,
    revisions: (id: string) => ["routines", "revisions", id] as const,
    activity: (domainId: string, id: string) => ["routines", "activity", domainId, id] as const,
    documentAnnotations: (routineId: string, key: "description", status: "open" | "resolved" | "all" = "all") =>
      ["routines", "document-annotations", routineId, key, status] as const,
  },
  workflows: {
    list: (domainId: string) => ["workflows", domainId] as const,
    detail: (workflowId: string) => ["workflows", "detail", workflowId] as const,
    cases: (workflowId: string) => ["workflows", "life-admin", workflowId] as const,
    caseDetail: (caseId: string) => ["workflows", "item", caseId] as const,
    caseChildren: (caseId: string) => ["workflows", "item", caseId, "children"] as const,
    caseEvents: (caseId: string) => ["workflows", "item", caseId, "events"] as const,
    caseIssueLinks: (caseId: string) => ["workflows", "item", caseId, "issue-links"] as const,
    caseOutputs: (caseId: string) => ["workflows", "item", caseId, "outputs"] as const,
    caseDocument: (caseId: string, key: string) => ["workflows", "item", caseId, "document", key] as const,
    caseDocumentRevisions: (caseId: string, key: string) =>
      ["workflows", "item", caseId, "document-revisions", key] as const,
    intakeForm: (workflowId: string) => ["workflows", "intake-form", workflowId] as const,
    health: (workflowId: string) => ["workflows", "health", workflowId] as const,
    document: (workflowId: string, key: string) => ["workflows", "document", workflowId, key] as const,
    documentRevisions: (workflowId: string, key: string) =>
      ["workflows", "document-revisions", workflowId, key] as const,
    attention: (domainId: string) => ["workflows", "attention", domainId] as const,
    reviewLifeAdmin: (domainId: string) => ["workflows", "review-life-admins", domainId] as const,
    learnings: (domainId: string, offset: number) => ["workflows", "learnings", domainId, offset] as const,
  },
  executionWorkspaces: {
    list: (domainId: string, filters?: Record<string, string | boolean | undefined>) =>
      ["execution-workspaces", domainId, filters ?? {}] as const,
    summaryList: (domainId: string, filters?: Record<string, string | boolean | undefined>) =>
      ["execution-workspaces", domainId, "summary", filters ?? {}] as const,
    overview: (domainId: string, filters?: Record<string, string | number | boolean | undefined>) =>
      ["execution-workspaces", domainId, "overview", filters ?? {}] as const,
    detail: (id: string) => ["execution-workspaces", "detail", id] as const,
    closeReadiness: (id: string) => ["execution-workspaces", "close-readiness", id] as const,
    workspaceOperations: (id: string) => ["execution-workspaces", "workspace-operations", id] as const,
  },
  environments: {
    list: (domainId: string) => ["environments", domainId] as const,
    capabilities: (domainId: string) => ["environment-capabilities", domainId] as const,
    customImageTemplate: (environmentId: string) =>
      ["environments", environmentId, "custom-image-template"] as const,
    customImageSetupSession: (sessionId: string) =>
      ["environment-custom-image-setup-sessions", sessionId] as const,
  },
  projects: {
    list: (domainId: string) => ["projects", domainId] as const,
    detail: (id: string) => ["projects", "detail", id] as const,
  },
  cases: {
    list: (domainId: string) => ["life-admin", domainId] as const,
    detail: (id: string) => ["life-admin", "detail", id] as const,
    documents: (id: string) => ["life-admin", "documents", id] as const,
    documentAnnotations: (caseId: string, key: string, status: "open" | "resolved" | "all" = "all") =>
      ["life-admin", "document-annotations", caseId, key, status] as const,
    events: (id: string) => ["life-admin", "events", id] as const,
    children: (parentId: string) => ["life-admin", "children", parentId] as const,
    revisions: (id: string, key: string) => ["life-admin", "revisions", id, key] as const,
    forIssue: (issueId: string) => ["life-admin", "for-issue", issueId] as const,
  },
  externalObjects: {
    byIssue: (issueId: string) => ["external-objects", "by-issue", issueId] as const,
    issueSummary: (issueId: string) => ["external-objects", "issue-summary", issueId] as const,
    issueSummaries: (domainId: string, issueIds: readonly string[]) =>
      ["external-objects", "issue-summaries", domainId, issueIds] as const,
    projectSummary: (projectId: string) => ["external-objects", "project-summary", projectId] as const,
  },
  goals: {
    list: (domainId: string) => ["goals", domainId] as const,
    detail: (id: string) => ["goals", "detail", id] as const,
  },
  artifacts: {
    list: (
      domainId: string,
      kind?: string,
      q?: string,
      groupBy?: string,
      groupIssueId?: string,
    ) =>
      [
        "artifacts",
        domainId,
        kind ?? "all",
        q ?? "",
        groupBy ?? "none",
        groupIssueId ?? "",
      ] as const,
  },
  budgets: {
    overview: (domainId: string) => ["budgets", "overview", domainId] as const,
  },
  approvals: {
    list: (domainId: string, status?: string) =>
      ["approvals", domainId, status] as const,
    detail: (approvalId: string) => ["approvals", "detail", approvalId] as const,
    comments: (approvalId: string) => ["approvals", "comments", approvalId] as const,
    issues: (approvalId: string) => ["approvals", "issues", approvalId] as const,
  },
  access: {
    invites: (domainId: string, state: string = "all", limit: number = 20) =>
      ["access", "invites", "paginated-v1", domainId, state, limit] as const,
    joinRequests: (domainId: string, status: string = "pending_approval") =>
      ["access", "join-requests", domainId, status] as const,
    domainMembers: (domainId: string) => ["access", "domain-members", domainId] as const,
    domainUserDirectory: (domainId: string) => ["access", "domain-user-directory", domainId] as const,
    adminUsers: (query: string) => ["access", "admin-users", query] as const,
    userDomainAccess: (userId: string) => ["access", "user-domain-access", userId] as const,
    invite: (token: string) => ["access", "invite", token] as const,
    currentBoardAccess: ["access", "current-board-access"] as const,
  },
  auth: {
    session: ["auth", "session"] as const,
  },
  sidebarPreferences: {
    domainOrder: (userId: string) => ["sidebar-preferences", "domain-order", userId] as const,
    projectOrder: (domainId: string, userId: string) =>
      ["sidebar-preferences", "project-order", domainId, userId] as const,
  },
  resourceMemberships: {
    mine: (domainId: string) => ["resource-memberships", domainId, "me"] as const,
  },
  instance: {
    settings: ["instance", "settings"] as const,
    generalSettings: ["instance", "general-settings"] as const,
    schedulerHeartbeats: ["instance", "scheduler-heartbeats"] as const,
    experimentalSettings: ["instance", "experimental-settings"] as const,
  },
  cloudUpstreams: (domainId: string) => ["cloud-upstreams", domainId] as const,
  health: ["health"] as const,
  secrets: {
    list: (domainId: string) => ["secrets", domainId] as const,
    providers: (domainId: string) => ["secret-providers", domainId] as const,
    providerConfigs: (domainId: string) => ["secret-provider-configs", domainId] as const,
    usage: (secretId: string) => ["secrets", "usage", secretId] as const,
    accessEvents: (secretId: string) => ["secrets", "access-events", secretId] as const,
    userDefinitions: (domainId: string) => ["user-secret-definitions", domainId] as const,
    userDefinitionCoverage: (domainId: string, definitionId: string) =>
      ["user-secret-definitions", domainId, definitionId, "coverage"] as const,
    myUserSecrets: (domainId: string) => ["my-user-secrets", domainId] as const,
  },
  domainSearch: {
    search: (domainId: string, q: string, scope: string, limit: number, offset: number) =>
      ["domain-search", domainId, q, scope, limit, offset] as const,
  },
  dashboard: (domainId: string) => ["dashboard", domainId] as const,
  attention: (domainId: string) => ["attention", domainId] as const,
  workJournal: (domainId: string, lens?: string) => ["work-journal", domainId, lens ?? "all"] as const,
  userProfile: (domainId: string, userSlug: string) =>
    ["user-profile", domainId, userSlug] as const,
  sidebarBadges: (domainId: string) => ["sidebar-badges", domainId] as const,
  inboxDismissals: (domainId: string) => ["inbox-dismissals", domainId] as const,
  activity: (domainId: string) => ["activity", domainId] as const,
  finances: (domainId: string, from?: string, to?: string) =>
    ["finances", domainId, from, to] as const,
  usageByProvider: (domainId: string, from?: string, to?: string) =>
    ["usage-by-provider", domainId, from, to] as const,
  usageByBiller: (domainId: string, from?: string, to?: string) =>
    ["usage-by-biller", domainId, from, to] as const,
  financeSummary: (domainId: string, from?: string, to?: string) =>
    ["finance-summary", domainId, from, to] as const,
  financeByBiller: (domainId: string, from?: string, to?: string) =>
    ["finance-by-biller", domainId, from, to] as const,
  financeByKind: (domainId: string, from?: string, to?: string) =>
    ["finance-by-kind", domainId, from, to] as const,
  financeEvents: (domainId: string, from?: string, to?: string, limit: number = 100) =>
    ["finance-events", domainId, from, to, limit] as const,
  usageWindowSpend: (domainId: string) =>
    ["usage-window-spend", domainId] as const,
  usageQuotaWindows: (domainId: string) =>
    ["usage-quota-windows", domainId] as const,
  heartbeats: (domainId: string, agentId?: string) =>
    ["heartbeats", domainId, agentId] as const,
  runDetail: (runId: string) => ["heartbeat-run", runId] as const,
  runWorkspaceOperations: (runId: string) => ["heartbeat-run", runId, "workspace-operations"] as const,
  liveRuns: (domainId: string) => ["live-runs", domainId] as const,
  runIssues: (runId: string) => ["run-issues", runId] as const,
  org: (domainId: string) => ["org", domainId] as const,
  skills: {
    available: ["skills", "available"] as const,
  },
  plugins: {
    all: ["plugins"] as const,
    examples: ["plugins", "examples"] as const,
    detail: (pluginId: string) => ["plugins", pluginId] as const,
    health: (pluginId: string) => ["plugins", pluginId, "health"] as const,
    uiContributions: ["plugins", "ui-contributions"] as const,
    config: (pluginId: string) => ["plugins", pluginId, "config"] as const,
    localFolders: (pluginId: string, domainId: string) =>
      ["plugins", pluginId, "domains", domainId, "local-folders"] as const,
    dashboard: (pluginId: string) => ["plugins", pluginId, "dashboard"] as const,
    logs: (pluginId: string) => ["plugins", pluginId, "logs"] as const,
  },
  adapters: {
    all: ["adapters"] as const,
  },
};
