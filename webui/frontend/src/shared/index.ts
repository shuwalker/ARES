// @ts-nocheck
// Barrel re-export from local shared modules + stub types for @paperclipai/shared compatibility.
// This file exists so that `import { ... } from "@paperclipai/shared"` resolves locally.

// ── Re-export from existing shared modules ──
export * from "./contracts";
export * from "./translators";
export * from "./ares-api";
export { apiFetch, apiUrl, webSocketUrl, webSocketProtocols, readableError, ApiError } from "./api-client";

// ── Stub types and constants not yet in local shared ──
// These are placeholder type declarations to satisfy imports across the codebase.

export type Agent = { id: string; name: string; urlKey: string; [k: string]: unknown };
export type AgentDetail = Agent & { permissions?: AgentPermissions; [k: string]: unknown };
export type AgentPermissions = Record<string, unknown>;
export type AgentSkillEntry = { id: string; name: string; [k: string]: unknown };
export type AgentIconName = string;
export const AGENT_ICON_NAMES: Record<string, string> = {};
export const AGENT_DEFAULT_MAX_CONCURRENT_RUNS = 3;
export const ADAPTER_AGNOSTIC_KEYS: string[] = [];

export type ActivityEvent = { id: string; kind: string; [k: string]: unknown };
export type Approval = { id: string; [k: string]: unknown };
export type DashboardSummary = { id: string; [k: string]: unknown };
export type InboxDismissal = { id: string; [k: string]: unknown };
export type JoinRequest = { id: string; [k: string]: unknown };

export type Domain = { id: string; name: string; urlKey: string; [k: string]: unknown };
export type DomainPortabilitySidebarOrder = { [k: string]: unknown };
export type DomainPortabilityFileEntry = { path: string; [k: string]: unknown };
export type DomainPortabilityIssueManifestEntry = { issueId: string; [k: string]: unknown };
export type DomainSkill = { id: string; name: string; [k: string]: unknown };
export type DomainSkillDetail = DomainSkill & { [k: string]: unknown };
export type DomainSkillListItem = { id: string; name: string; [k: string]: unknown };
export type DomainSkillCreateRequest = { name: string; [k: string]: unknown };
export type DomainSkillForkSummary = { [k: string]: unknown };
export type DomainSkillOriginalSummary = { [k: string]: unknown };
export type DomainSkillSourceType = string;
export type DomainSkillSharingScope = string;
export type DomainSkillTestInput = { [k: string]: unknown };
export type DomainSkillTestRun = { id: string; [k: string]: unknown };
export type DomainSkillTestRunCreateRequest = { [k: string]: unknown };
export type DomainSkillTestRunDetail = { [k: string]: unknown };
export type DomainSkillTestRunHarnessContentUnavailableReason = string;
export type DomainSkillTestRunStatus = string;
export type DomainSkillTestRunTemplate = { [k: string]: unknown };
export type DomainSkillUsageAgent = { [k: string]: unknown };
export type DomainSkillLastEditor = { [k: string]: unknown };
export type DomainSearchSort = string;
export const DOMAIN_SEARCH_SORTS: string[] = [];
export const DOMAIN_SEARCH_UPDATED_WITHIN_OPTIONS: string[] = [];

export type Environment = { id: string; [k: string]: unknown };
export type InstanceExecutionMode = string;
export type ExecutionWorkspace = { id: string; name: string; [k: string]: unknown };
export type ExecutionWorkspaceMode = string;
export type ProjectExecutionWorkspaceDefaultMode = string;

export type ExternalObjectSummary = { id: string; [k: string]: unknown };
export type ExternalObjectSummaryItem = { id: string; [k: string]: unknown };
export type ExternalObjectLivenessState = string;
export type ExternalObjectStatusCategory = string;
export type ExternalObjectStatusTone = string;
export type ExternalObjectMention = { id: string; [k: string]: unknown };
export type ExternalObjectMentionGroup = { id: string; [k: string]: unknown };

export type BillingType = string;
export type FinanceDirection = string;
export type FinanceEventKind = string;

export type Goal = { id: string; title: string; [k: string]: unknown };

export type HeartbeatRun = { id: string; [k: string]: unknown };

export type Issue = { id: string; title: string; [k: string]: unknown };
export type IssueStatus = string;
export type IssuePriority = string;
export const ISSUE_PRIORITIES: string[] = [];
export const ISSUE_STATUSES: string[] = [];
export type IssueAttachment = { id: string; [k: string]: unknown };
export type IssueComment = { id: string; body: string; [k: string]: unknown };
export type IssueCommentMetadata = { [k: string]: unknown };
export type IssueCommentMetadataRow = { [k: string]: unknown };
export type IssueCommentPresentation = { [k: string]: unknown };
export type IssueDocument = { id: string; [k: string]: unknown };
export type IssueWorkMode = string;
export type IssueWorkProduct = { [k: string]: unknown };
export type IssueExecutionPolicy = { [k: string]: unknown };
export type IssueExecutionStageParticipant = { [k: string]: unknown };
export type IssueExecutionStagePrincipal = { [k: string]: unknown };
export type IssueRecoveryAction = { [k: string]: unknown };
export type IssueRecoveryActionKind = string;
export type IssueRelationIssueSummary = { id: string; [k: string]: unknown };
export type IssueRetryNowOutcome = { [k: string]: unknown };
export type IssueRetryNowResponse = { [k: string]: unknown };
export type IssueBlockedInboxAttention = { [k: string]: unknown };
export type IssueBlockedInboxReason = string;
export type IssueBlockedInboxSeverity = string;
export type IssueBlockerAttention = { [k: string]: unknown };
export type IssueThreadInteraction = { [k: string]: unknown };
export type DocumentRevision = { id: string; [k: string]: unknown };
export type DocumentAnnotationAnchorSelector = { [k: string]: unknown };
export type DocumentTextProjection = { [k: string]: unknown };
export type DocumentTextRange = { [k: string]: unknown };
export type AttachmentArtifactWorkProductMetadata = { [k: string]: unknown };
export const attachmentArtifactWorkProductMetadataSchema = {} as any;

export type AttentionDetailImage = { [k: string]: unknown };
export type AttentionFeed = { [k: string]: unknown };
export type AttentionItem = { [k: string]: unknown };
export type AttentionItemDetail = { [k: string]: unknown };
export type AttentionProjectRef = { [k: string]: unknown };
export type AttentionSeverity = string;
export type AttentionSourceKind = string;
export type AttentionWorkspaceRef = { [k: string]: unknown };

export type Project = { id: string; name: string; urlKey: string; [k: string]: unknown };
export type ProjectIconName = string;
export const PROJECT_ICON_NAMES: Record<string, string> = {};

export type ResourceMembershipResourceType = string;
export type ResourceMembershipState = string;
export type ResourceMemberships = { [k: string]: unknown };

export type RoutineTrigger = { id: string; [k: string]: unknown };
export type RoutineRunSummary = { id: string; [k: string]: unknown };
export type RoutineVariable = { name: string; [k: string]: unknown };
export type RoutineListItem = { id: string; name: string; [k: string]: unknown };
export const WORKSPACE_BRANCH_ROUTINE_VARIABLE = "workspace_branch";
export function extractRoutineVariableNames(template: string): string[] { return []; }

export type WorkflowCaseLiveness = { [k: string]: unknown };
export type SuccessfulRunHandoffState = { [k: string]: unknown };

export type WorkJournalActor = { [k: string]: unknown };
export type WorkJournalEdge = { [k: string]: unknown };
export type WorkJournalEvent = { [k: string]: unknown };
export type WorkJournalResult = { [k: string]: unknown };
export type WorkJournalSpan = { [k: string]: unknown };

export type LowTrustBoundary = { [k: string]: unknown };
export type SourceTrustMetadata = { [k: string]: unknown };
export type TrustAuthorizationPolicy = { [k: string]: unknown };
export type TrustPreset = { [k: string]: unknown };
export const DEFAULT_TRUST_PRESET: TrustPreset = {} as TrustPreset;
export const LOW_TRUST_REVIEW_PRESET: TrustPreset = {} as TrustPreset;
export const LOW_TRUST_REVIEW_PRESET_VERSION = "1";
export const LOW_TRUST_REVIEW_RAW_OUTPUT_DISPOSITION = "include";

export type AskUserQuestionsAnswer = { [k: string]: unknown };
export type AskUserQuestionsInteraction = { [k: string]: unknown };
export type AskUserQuestionsQuestion = { [k: string]: unknown };
export type RequestCheckboxConfirmationPayload = { [k: string]: unknown };
export type RequestCheckboxConfirmationResult = { [k: string]: unknown };
export type RequestConfirmationInteraction = { [k: string]: unknown };
export type RequestConfirmationTarget = { [k: string]: unknown };
export type RequestItemVerdictValue = { [k: string]: unknown };
export type RequestItemVerdictsInteraction = { [k: string]: unknown };
export type RequestItemVerdictsPayload = { [k: string]: unknown };
export type RequestItemVerdictsResult = { [k: string]: unknown };
export type SuggestedTaskDraft = { [k: string]: unknown };
export type SuggestTasksInteraction = { [k: string]: unknown };
export type SuggestTasksResultCreatedTask = { [k: string]: unknown };
export type SubmitIssueThreadInteractionVerdicts = { [k: string]: unknown };

export type SystemNoticeMetadataRow = { [k: string]: unknown };
export type SystemNoticeMetadataSection = { [k: string]: unknown };
export type SystemNoticeProps = { [k: string]: unknown };
export type SystemNoticeTone = string;

export type DomainSearchParams = { [k: string]: unknown };

// ── Stub functions ──
export function deriveAgentUrlKey(..._args: unknown[]): string { return ""; }
export function deriveProjectUrlKey(..._args: unknown[]): string { return ""; }
export function normalizeAgentUrlKey(..._args: unknown[]): string { return ""; }
export function normalizeProjectUrlKey(..._args: unknown[]): string { return ""; }
export function hasNonAsciiContent(s: string): boolean { return false; }
export function isUuidLike(s: string): boolean { return false; }
export function parseAgentMentionHref(href: string): Record<string, string> | null { return null; }
export function parseIssueReferenceHref(href: string): Record<string, string> | null { return null; }
export function parseProjectMentionHref(href: string): Record<string, string> | null { return null; }
export function parseRoutineMentionHref(href: string): Record<string, string> | null { return null; }
export function parseSkillMentionHref(href: string): Record<string, string> | null { return null; }
export function parseUserMentionHref(href: string): Record<string, string> | null { return null; }
export function createDocumentAnchorSelector(..._args: unknown[]): unknown { return {}; }
export function normalizeAnchorText(..._args: unknown[]): string { return ""; }
export function projectMarkdownToText(..._args: unknown[]): string { return ""; }
export function resolveProjectionRange(..._args: unknown[]): unknown { return {}; }
export function getAgentIcon(..._args: unknown[]): unknown { return null; }
export function applyIssueFilters(..._args: unknown[]): unknown { return []; }
export function defaultIssueFilterState(..._args: unknown[]): unknown { return {}; }
export function normalizeIssueFilterState(..._args: unknown[]): unknown { return {}; }
export type IssueFilterState = { [k: string]: unknown };
export function getIssueOutputs(..._args: unknown[]): unknown[] { return []; }
export function getPromotedOutputAttachmentIds(..._args: unknown[]): string[] { return []; }
export function isImageContentType(..._args: unknown[]): boolean { return false; }
export function isVideoLikeOutput(..._args: unknown[]): boolean { return false; }