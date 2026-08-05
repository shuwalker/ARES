export interface CompanionCharacter {
  id: string;
  name: string;
  role: string;
  voice_tone: string;
  voice_id: string;
  active: boolean;
  bound: boolean;
  custom_instructions?: string;
}

export interface CompanionStatus {
  contract_version: 1;
  dependency: {
    product: "JaegerAI";
    root: string;
    transport: "bridge" | "gateway";
  };
  agent: {
    id: string;
    name: string;
    model: string | null;
    avatar: string | null;
  };
  character: CompanionCharacter;
  characters: CompanionCharacter[];
  relationship: {
    owner_name: string;
    ares_name: string;
    aligned: boolean;
  };
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function character(value: unknown): CompanionCharacter {
  const row = record(value);
  return {
    id: text(row.id),
    name: text(row.name) || text(row.id),
    role: text(row.role),
    voice_tone: text(row.voice_tone),
    voice_id: text(row.voice_id),
    active: Boolean(row.active),
    bound: Boolean(row.bound),
    custom_instructions: text(row.custom_instructions) || undefined,
  };
}

export function parseCompanionStatus(value: unknown): CompanionStatus {
  const payload = record(value);
  const dependency = record(payload.dependency);
  const agent = record(payload.agent);
  const relationship = record(payload.relationship);
  const rawCharacters = Array.isArray(payload.characters) ? payload.characters : [];
  const product = text(dependency.product);
  if (payload.contract_version !== 1 || product !== "JaegerAI") {
    throw new Error("Unsupported Companion contract");
  }
  return {
    contract_version: 1,
    dependency: {
      product: "JaegerAI",
      root: text(dependency.root),
      transport: dependency.transport === "gateway" ? "gateway" : "bridge",
    },
    agent: {
      id: text(agent.id),
      name: text(agent.name),
      model: text(agent.model) || null,
      avatar: text(agent.avatar) || null,
    },
    character: character(payload.character),
    characters: rawCharacters.map(character).filter((row) => Boolean(row.id)),
    relationship: {
      owner_name: text(relationship.owner_name),
      ares_name: text(relationship.ares_name),
      aligned: Boolean(relationship.aligned),
    },
  };
}

export interface CompanionUpdate {
  name?: string;
  owner_name?: string;
  character_id?: string;
}
