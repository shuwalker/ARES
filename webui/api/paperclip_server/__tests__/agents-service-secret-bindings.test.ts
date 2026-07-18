import { randomUUID } from "node:crypto";
import { mkdirSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { and, eq } from "drizzle-orm";
import {
  agents,
  domains,
  domainSecretBindings,
  domainSecretProviderConfigs,
  domainSecretVersions,
  domainSecrets,
  createDb,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { agentService } from "../services/agents.ts";
import { secretService } from "../services/secrets.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres agent secret binding tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("agent service secret binding sync", () => {
  let stopDb: (() => Promise<void>) | null = null;
  let db!: ReturnType<typeof createDb>;
  const previousKeyFile = process.env.PAPERCLIP_SECRETS_MASTER_KEY_FILE;
  const secretsTmpDir = path.join(os.tmpdir(), `paperclip-agent-secret-bindings-${randomUUID()}`);

  beforeAll(async () => {
    mkdirSync(secretsTmpDir, { recursive: true });
    process.env.PAPERCLIP_SECRETS_MASTER_KEY_FILE = path.join(secretsTmpDir, "master.key");
    const started = await startEmbeddedPostgresTestDatabase("agent-secret-bindings");
    stopDb = started.cleanup;
    db = createDb(started.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(domainSecretBindings);
    await db.delete(domainSecretVersions);
    await db.delete(domainSecrets);
    await db.delete(domainSecretProviderConfigs);
    await db.delete(agents);
    await db.delete(domains);
  });

  afterAll(async () => {
    await stopDb?.();
    if (previousKeyFile === undefined) {
      delete process.env.PAPERCLIP_SECRETS_MASTER_KEY_FILE;
    } else {
      process.env.PAPERCLIP_SECRETS_MASTER_KEY_FILE = previousKeyFile;
    }
    rmSync(secretsTmpDir, { recursive: true, force: true });
  });

  async function seedDomain() {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });
    return domainId;
  }

  it("creates agent secret bindings when a new agent persists secret_ref env", async () => {
    const domainId = await seedDomain();
    const secrets = secretService(db);
    const secret = await secrets.create(domainId, {
      name: `anthropic-${randomUUID()}`,
      provider: "local_encrypted",
      value: "sk-ant-123",
    });

    const created = await agentService(db).create(domainId, {
      name: "Claude Novita",
      role: "engineer",
      status: "pending_approval",
      adapterType: "claude_local",
      adapterConfig: {
        env: {
          ANTHROPIC_API_KEY: { type: "secret_ref", secretId: secret.id, version: "latest" },
        },
      },
      runtimeConfig: {},
      spentMonthlyCents: 0,
      lastHeartbeatAt: null,
    });

    const bindings = await db
      .select()
      .from(domainSecretBindings)
      .where(and(
        eq(domainSecretBindings.domainId, domainId),
        eq(domainSecretBindings.targetType, "agent"),
        eq(domainSecretBindings.targetId, created.id),
      ));

    expect(bindings).toHaveLength(1);
    expect(bindings[0]).toMatchObject({
      secretId: secret.id,
      configPath: "env.ANTHROPIC_API_KEY",
      versionSelector: "latest",
      required: true,
    });
  });

  it("converts Hermes gateway apiKey strings into persisted secret refs", async () => {
    const domainId = await seedDomain();
    const literalApiKey = `hermes-key-${randomUUID()}`;

    const created = await agentService(db).create(domainId, {
      name: "Hermes Gateway",
      role: "engineer",
      status: "idle",
      adapterType: "hermes_gateway",
      adapterConfig: {
        apiBaseUrl: "https://hermes.example",
        apiKey: literalApiKey,
      },
      runtimeConfig: {},
      spentMonthlyCents: 0,
      lastHeartbeatAt: null,
    });

    const persistedRows = await db
      .select()
      .from(agents)
      .where(eq(agents.id, created.id));
    const persistedConfig = persistedRows[0]?.adapterConfig as Record<string, unknown>;
    expect(JSON.stringify(persistedConfig)).not.toContain(literalApiKey);
    expect(persistedConfig.apiKey).toMatchObject({
      type: "secret_ref",
      version: "latest",
    });

    const secretId = (persistedConfig.apiKey as { secretId: string }).secretId;
    const bindings = await db
      .select()
      .from(domainSecretBindings)
      .where(and(
        eq(domainSecretBindings.domainId, domainId),
        eq(domainSecretBindings.targetType, "agent"),
        eq(domainSecretBindings.targetId, created.id),
      ));
    expect(bindings).toHaveLength(1);
    expect(bindings[0]).toMatchObject({
      secretId,
      configPath: "apiKey",
      versionSelector: "latest",
      required: true,
    });

    const resolved = await secretService(db).resolveAdapterConfigForRuntime(
      domainId,
      persistedConfig,
      {
        consumerType: "agent",
        consumerId: created.id,
      },
      { adapterType: "hermes_gateway" },
    );
    expect(resolved.config.apiKey).toBe(literalApiKey);
    expect(JSON.stringify(persistedConfig)).not.toContain(literalApiKey);
  });

  it("replaces agent secret bindings when adapterConfig env changes", async () => {
    const domainId = await seedDomain();
    const secrets = secretService(db);
    const oldSecret = await secrets.create(domainId, {
      name: `old-${randomUUID()}`,
      provider: "local_encrypted",
      value: "old-value",
    });
    const nextSecret = await secrets.create(domainId, {
      name: `next-${randomUUID()}`,
      provider: "local_encrypted",
      value: "next-value",
    });

    const created = await agentService(db).create(domainId, {
      name: "Binding Swapper",
      role: "engineer",
      adapterType: "codex_local",
      adapterConfig: {
        env: {
          OLD_KEY: { type: "secret_ref", secretId: oldSecret.id, version: "latest" },
        },
      },
      runtimeConfig: {},
      spentMonthlyCents: 0,
      lastHeartbeatAt: null,
    });

    await agentService(db).update(created.id, {
      adapterConfig: {
        env: {
          NEW_KEY: { type: "secret_ref", secretId: nextSecret.id, version: "latest" },
        },
      },
    });

    const bindings = await db
      .select()
      .from(domainSecretBindings)
      .where(and(
        eq(domainSecretBindings.domainId, domainId),
        eq(domainSecretBindings.targetType, "agent"),
        eq(domainSecretBindings.targetId, created.id),
      ));

    expect(bindings).toHaveLength(1);
    expect(bindings[0]).toMatchObject({
      secretId: nextSecret.id,
      configPath: "env.NEW_KEY",
    });
  });

  it("backfills missing secret bindings when a legacy pending agent is approved", async () => {
    const domainId = await seedDomain();
    const secrets = secretService(db);
    const secret = await secrets.create(domainId, {
      name: `legacy-${randomUUID()}`,
      provider: "local_encrypted",
      value: "legacy-value",
    });
    const agentId = randomUUID();

    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "Legacy Pending Agent",
      role: "engineer",
      status: "pending_approval",
      adapterType: "claude_local",
      adapterConfig: {
        env: {
          ANTHROPIC_API_KEY: { type: "secret_ref", secretId: secret.id, version: "latest" },
        },
      },
      runtimeConfig: {},
      permissions: {},
    });

    const beforeBindings = await db
      .select()
      .from(domainSecretBindings)
      .where(eq(domainSecretBindings.targetId, agentId));
    expect(beforeBindings).toHaveLength(0);

    const approved = await agentService(db).activatePendingApproval(agentId);

    expect(approved).toMatchObject({
      activated: true,
      agent: {
        id: agentId,
        status: "idle",
      },
    });

    const afterBindings = await db
      .select()
      .from(domainSecretBindings)
      .where(and(
        eq(domainSecretBindings.domainId, domainId),
        eq(domainSecretBindings.targetType, "agent"),
        eq(domainSecretBindings.targetId, agentId),
      ));

    expect(afterBindings).toHaveLength(1);
    expect(afterBindings[0]).toMatchObject({
      secretId: secret.id,
      configPath: "env.ANTHROPIC_API_KEY",
    });
  });

  it("rolls back create when binding sync fails", async () => {
    const domainId = await seedDomain();
    const missingSecretId = randomUUID();

    await expect(
      agentService(db).create(domainId, {
        name: "Broken Create",
        role: "engineer",
        adapterType: "claude_local",
        adapterConfig: {
          env: {
            ANTHROPIC_API_KEY: { type: "secret_ref", secretId: missingSecretId, version: "latest" },
          },
        },
        runtimeConfig: {},
        spentMonthlyCents: 0,
        lastHeartbeatAt: null,
      }),
    ).rejects.toBeTruthy();

    const persistedAgents = await db
      .select()
      .from(agents)
      .where(eq(agents.domainId, domainId));
    expect(persistedAgents).toHaveLength(0);
  });

  it("rolls back adapterConfig updates when binding sync fails", async () => {
    const domainId = await seedDomain();
    const secrets = secretService(db);
    const validSecret = await secrets.create(domainId, {
      name: `valid-${randomUUID()}`,
      provider: "local_encrypted",
      value: "valid-value",
    });
    const created = await agentService(db).create(domainId, {
      name: "Transactional Update",
      role: "engineer",
      adapterType: "codex_local",
      adapterConfig: {
        env: {
          API_KEY: { type: "secret_ref", secretId: validSecret.id, version: "latest" },
        },
      },
      runtimeConfig: {},
      spentMonthlyCents: 0,
      lastHeartbeatAt: null,
    });

    await expect(
      agentService(db).update(created.id, {
        adapterConfig: {
          env: {
            API_KEY: { type: "secret_ref", secretId: randomUUID(), version: "latest" },
          },
        },
      }),
    ).rejects.toBeTruthy();

    const reloaded = await agentService(db).getById(created.id);
    expect(reloaded?.adapterConfig).toMatchObject({
      env: {
        API_KEY: { type: "secret_ref", secretId: validSecret.id, version: "latest" },
      },
    });

    const bindings = await db
      .select()
      .from(domainSecretBindings)
      .where(and(
        eq(domainSecretBindings.domainId, domainId),
        eq(domainSecretBindings.targetType, "agent"),
        eq(domainSecretBindings.targetId, created.id),
      ));
    expect(bindings).toHaveLength(1);
    expect(bindings[0]?.secretId).toBe(validSecret.id);
  });

  it("keeps pending approval status when activation binding sync fails", async () => {
    const domainId = await seedDomain();
    const agentId = randomUUID();

    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "Broken Pending Agent",
      role: "engineer",
      status: "pending_approval",
      adapterType: "claude_local",
      adapterConfig: {
        env: {
          ANTHROPIC_API_KEY: { type: "secret_ref", secretId: randomUUID(), version: "latest" },
        },
      },
      runtimeConfig: {},
      permissions: {},
    });

    await expect(agentService(db).activatePendingApproval(agentId)).rejects.toBeTruthy();

    const reloaded = await agentService(db).getById(agentId);
    expect(reloaded?.status).toBe("pending_approval");
  });
});
