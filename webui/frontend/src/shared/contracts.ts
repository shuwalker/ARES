export type Availability = "available" | "limited" | "unavailable" | "unknown";
export type TaskStatus = "planned" | "active" | "waiting" | "completed" | "failed";
export type ExecutionStatus = "queued" | "running" | "waiting" | "completed" | "failed";
export type ConnectionState = "loading" | "available" | "limited" | "unavailable";

export interface LocalProfile {
  displayName: string;
  assistantName: string;
  voice: string;
  reachability: "this-device" | "local-network" | "private-network";
  contextStoreEnabled?: boolean;
}

export interface CapabilityStatus {
  id: string;
  label: string;
  availability: Availability;
  detail: string;
}

export interface TaskSummary {
  id: string;
  title: string;
  status: TaskStatus;
  dueAt?: string;
}

export interface ExecutionSummary {
  id: string;
  label: string;
  runtime: string;
  status: ExecutionStatus;
  startedAt?: string;
}

export interface TodaySummary {
  completed: TaskSummary[];
  dueSoon: TaskSummary[];
  activeExecutions: ExecutionSummary[];
}

export interface SessionSummary {
  id: string;
  title: string;
  workspace: string;
  model: string;
  provider: string;
  backendId: string;
  profile: string;
  source: string;
  updatedAt?: string;
  activeStreamId?: string;
  messageCount: number;
  pinned: boolean;
  archived?: boolean;
  isStreaming: boolean;
  readOnly: boolean;
}

export type ConversationRole = "user" | "assistant" | "system" | "tool";

export interface ConversationMessage {
  id: string;
  role: ConversationRole;
  text: string;
  createdAt?: string;
}

export interface ConversationSession extends SessionSummary {
  messages: ConversationMessage[];
  pendingStartedAt?: string;
}

export interface WorkspaceSummary {
  path: string;
  label: string;
}

export interface WorkspaceEntry {
  name: string;
  path: string;
  kind: "file" | "directory" | "other";
  size?: number;
}

export interface BackendSettings {
  assistantName: string;
  authEnabled: boolean;
  version?: string;
}

export interface AgentHealth {
  availability: Availability;
  detail: string;
}

export interface AuthStatus {
  authEnabled: boolean;
  loggedIn: boolean;
  passwordAuthEnabled: boolean;
  oidcEnabled: boolean;
}

export interface ToolInventory {
  total: number;
  names: string[];
  unavailableServers: string[];
}

export type RuntimeConnectionState = "connected" | "needs_attention" | "offline";

export interface RuntimeConnection {
  id: string;
  name: string;
  kind: "runtime" | "tool" | string;
  selected: boolean;
  state: RuntimeConnectionState;
  available: boolean;
  detail: string;
  capabilities: string[];
}

export interface AresSnapshot {
  connection: ConnectionState;
  settings: BackendSettings | null;
  sessions: SessionSummary[];
  workspaces: WorkspaceSummary[];
  backends: BackendInfo[];
  terminalRemoteBackend: boolean;
  agentHealth: AgentHealth;
  tools: ToolInventory;
  connections: RuntimeConnection[];
  error: string;
}

export const EMPTY_TODAY_SUMMARY: TodaySummary = {
  completed: [],
  dueSoon: [],
  activeExecutions: [],
};

export interface UsageBreakdownRow {
  key: string;
  sessions: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  cacheReadTokens: number;
  cacheHitPercent: number | null;
  cost: number;
  sessionShare: number;
  tokenShare: number;
  costShare: number;
  durationSeconds: number;
  averageDurationSeconds: number;
}

export interface UsageDailyPoint {
  date: string;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  sessions: number;
  cost: number;
  durationSeconds: number;
}

export interface UsageInsights {
  periodDays: number;
  totalSessions: number;
  totalMessages: number;
  totalInputTokens: number;
  totalOutputTokens: number;
  totalTokens: number;
  totalCacheReadTokens: number;
  totalCacheHitPercent: number | null;
  totalCost: number;
  totalDurationSeconds: number;
  averageSessionDurationSeconds: number;
  models: UsageBreakdownRow[];
  providers: UsageBreakdownRow[];
  dailyTokens: UsageDailyPoint[];
}

export const EMPTY_USAGE_INSIGHTS: UsageInsights = {
  periodDays: 30,
  totalSessions: 0,
  totalMessages: 0,
  totalInputTokens: 0,
  totalOutputTokens: 0,
  totalTokens: 0,
  totalCacheReadTokens: 0,
  totalCacheHitPercent: null,
  totalCost: 0,
  totalDurationSeconds: 0,
  averageSessionDurationSeconds: 0,
  models: [],
  providers: [],
  dailyTokens: [],
};


export interface BackendInfo {
  id: string;
  name: string;
  deployment: string;
  available: boolean;
  adapter?: string;
  description?: string;
}