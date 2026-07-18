export {};

import type { AgentApiKeyScope } from "@paperclipai/shared";

declare global {
  namespace Express {
    interface Request {
      actor: {
        type: "board" | "agent" | "none";
        userId?: string;
        userName?: string | null;
        userEmail?: string | null;
        agentId?: string;
        domainId?: string;
        domainIds?: string[];
        memberships?: Array<{
          domainId: string;
          membershipRole?: string | null;
          status?: string;
        }>;
        onBehalfOfMemberships?: Array<{
          domainId: string;
          membershipRole?: string | null;
          status?: string;
        }>;
        isInstanceAdmin?: boolean;
        keyId?: string;
        keyScope?: AgentApiKeyScope;
        runId?: string;
        onBehalfOfUserId?: string | null;
        source?: "local_implicit" | "session" | "board_key" | "agent_key" | "agent_jwt" | "cloud_tenant" | "none";
      };
    }
  }
}
