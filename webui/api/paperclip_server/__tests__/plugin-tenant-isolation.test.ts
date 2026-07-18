import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import {
  domains,
  createDb,
  pluginEntities,
  pluginJobs,
  pluginJobRuns,
  pluginLogs,
  pluginWebhookDeliveries,
  plugins,
} from "@paperclipai/db";
import { buildHostServices, flushPluginLogBuffer } from "../services/plugin-host-services.js";
import { pluginRegistryService } from "../services/plugin-registry.js";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";

function createEventBusStub() {
  return {
    forPlugin() {
      return {
        emit: vi.fn(),
        subscribe: vi.fn(),
        clear: vi.fn(),
      };
    },
  } as any;
}

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

function issuePrefix(id: string) {
  return `T${id.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`;
}

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping plugin tenant-isolation tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("plugin tenant isolation (domain_id FK)", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-plugin-tenant-isolation-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterEach(async () => {
    await db.delete(pluginEntities);
    await db.delete(pluginJobRuns);
    await db.delete(pluginJobs);
    await db.delete(pluginLogs);
    await db.delete(pluginWebhookDeliveries);
    await db.delete(plugins);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  async function seedPlugin() {
    const pluginId = randomUUID();
    await db.insert(plugins).values({
      id: pluginId,
      pluginKey: "paperclip.tenant-isolation-test",
      packageName: "@paperclipai/plugin-tenant-isolation-test",
      version: "0.0.1",
      apiVersion: 1,
      categories: ["automation"],
      manifestJson: {
        id: "paperclip.tenant-isolation-test",
        apiVersion: 1,
        version: "0.0.1",
        displayName: "Tenant Isolation Test",
        description: "Test plugin",
        author: "Paperclip",
        categories: ["automation"],
        capabilities: [],
        entrypoints: { worker: "./dist/worker.js" },
      },
      status: "ready",
      installOrder: 1,
    });
    return pluginId;
  }

  async function seedDomain() {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: `Tenant ${domainId.slice(0, 6)}`,
      issuePrefix: issuePrefix(domainId),
    });
    return domainId;
  }

  it("allows NULL domain_id on plugin_logs (instance-scope rows behave as before)", async () => {
    const pluginId = await seedPlugin();
    await db.insert(pluginLogs).values({
      pluginId,
      // domainId intentionally omitted — NULL means instance-scope.
      level: "info",
      message: "instance-scope log",
    });
    const rows = await db.select().from(pluginLogs).where(eq(pluginLogs.pluginId, pluginId));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.domainId).toBeNull();
  });

  it("cascades plugin_logs / plugin_entities / plugin_job_runs / plugin_webhook_deliveries when the owning domain is deleted", async () => {
    const pluginId = await seedPlugin();
    const domainA = await seedDomain();
    const domainB = await seedDomain();

    // Seed a job + run so we can verify plugin_job_runs cascades too.
    const jobAId = randomUUID();
    const jobBId = randomUUID();
    await db.insert(pluginJobs).values([
      { id: jobAId, pluginId, jobKey: "cron-a", schedule: "* * * * *" },
      { id: jobBId, pluginId, jobKey: "cron-b", schedule: "* * * * *" },
    ]);

    await db.insert(pluginLogs).values([
      { pluginId, domainId: domainA, level: "info", message: "A log" },
      { pluginId, domainId: domainB, level: "info", message: "B log" },
      { pluginId, level: "info", message: "instance log" },
    ]);

    await db.insert(pluginEntities).values([
      {
        pluginId,
        domainId: domainA,
        entityType: "issue",
        scopeKind: "domain",
        scopeId: domainA,
        externalId: "ext-a",
      },
      {
        pluginId,
        domainId: domainB,
        entityType: "issue",
        scopeKind: "domain",
        scopeId: domainB,
        externalId: "ext-b",
      },
    ]);

    await db.insert(pluginJobRuns).values([
      { jobId: jobAId, pluginId, domainId: domainA, trigger: "manual" },
      { jobId: jobBId, pluginId, domainId: domainB, trigger: "manual" },
      { jobId: jobAId, pluginId, trigger: "scheduled" },
    ]);

    await db.insert(pluginWebhookDeliveries).values([
      { pluginId, domainId: domainA, webhookKey: "wh", payload: { who: "A" } },
      { pluginId, domainId: domainB, webhookKey: "wh", payload: { who: "B" } },
      { pluginId, webhookKey: "wh", payload: { who: "instance" } },
    ]);

    // Delete domain A — only A's rows should be reaped. B's and NULL-scope rows stay.
    await db.delete(domains).where(eq(domains.id, domainA));

    const logs = await db.select().from(pluginLogs);
    expect(logs.map((r) => r.domainId).sort((a, b) => String(a).localeCompare(String(b)))).toEqual(
      [domainB, null].sort((a, b) => String(a).localeCompare(String(b))),
    );

    const entities = await db.select().from(pluginEntities);
    expect(entities).toHaveLength(1);
    expect(entities[0]?.domainId).toBe(domainB);

    const runs = await db.select().from(pluginJobRuns);
    expect(runs.map((r) => r.domainId).sort((a, b) => String(a).localeCompare(String(b)))).toEqual(
      [domainB, null].sort((a, b) => String(a).localeCompare(String(b))),
    );

    const deliveries = await db.select().from(pluginWebhookDeliveries);
    expect(deliveries.map((r) => r.domainId).sort((a, b) => String(a).localeCompare(String(b)))).toEqual(
      [domainB, null].sort((a, b) => String(a).localeCompare(String(b))),
    );
  });

  it("plugin_entities unique index is scoped per domain — two tenants can share (pluginId, entityType, externalId)", async () => {
    const pluginId = await seedPlugin();
    const domainA = await seedDomain();
    const domainB = await seedDomain();

    // Domain A claims external id "ext-1".
    await db.insert(pluginEntities).values({
      pluginId,
      domainId: domainA,
      entityType: "page",
      scopeKind: "domain",
      scopeId: domainA,
      externalId: "ext-1",
    });

    // Domain B uses the SAME (pluginId, entityType, externalId) — must succeed
    // under the per-domain unique index (would have collided under the old index).
    await db.insert(pluginEntities).values({
      pluginId,
      domainId: domainB,
      entityType: "page",
      scopeKind: "domain",
      scopeId: domainB,
      externalId: "ext-1",
    });

    const rows = await db.select().from(pluginEntities);
    expect(rows).toHaveLength(2);

    // Re-inserting the same (domainId, pluginId, entityType, externalId) tuple
    // for domain A must violate the unique constraint. Drizzle wraps the
    // underlying pg error as "Failed query: ..." — inspect the cause to confirm
    // it's the unique violation on our index (pg error code 23505).
    const err = await db
      .insert(pluginEntities)
      .values({
        pluginId,
        domainId: domainA,
        entityType: "page",
        scopeKind: "domain",
        scopeId: domainA,
        externalId: "ext-1",
      })
      .then(
        () => null,
        (e: unknown) => e,
      );
    expect(err).toBeInstanceOf(Error);
    // postgres error code 23505 = unique_violation, the constraint name is
    // not always surfaced on .cause by the driver, but the code is sufficient
    // to prove the unique index rejected the duplicate.
    const cause = (err as { cause?: { code?: string } }).cause;
    expect(cause?.code).toBe("23505");
  });

  it("pluginRegistryService.upsertEntity scopes its lookup by domainId — never overwrites another tenant's row", async () => {
    const pluginId = await seedPlugin();
    const domainA = await seedDomain();
    const domainB = await seedDomain();

    const registry = pluginRegistryService(db);

    // Domain A claims (issue, ext-shared) with title "A".
    const createdA = await registry.upsertEntity(pluginId, {
      domainId: domainA,
      entityType: "issue",
      scopeKind: "domain",
      scopeId: domainA,
      externalId: "ext-shared",
      title: "A",
      status: "open",
      data: {},
    });

    // Domain B upserts the SAME (entityType, externalId) tuple under its own
    // scope — must create a NEW row for B, NOT overwrite A.
    const createdB = await registry.upsertEntity(pluginId, {
      domainId: domainB,
      entityType: "issue",
      scopeKind: "domain",
      scopeId: domainB,
      externalId: "ext-shared",
      title: "B",
      status: "open",
      data: {},
    });

    expect(createdA?.id).toBeTruthy();
    expect(createdB?.id).toBeTruthy();
    expect(createdA?.id).not.toBe(createdB?.id);

    // Domain B updates its own row — A's row must remain untouched.
    const updatedB = await registry.upsertEntity(pluginId, {
      domainId: domainB,
      entityType: "issue",
      scopeKind: "domain",
      scopeId: domainB,
      externalId: "ext-shared",
      title: "B-updated",
      status: "closed",
      data: {},
    });
    expect(updatedB?.id).toBe(createdB?.id);
    expect(updatedB?.title).toBe("B-updated");

    const rows = await db.select().from(pluginEntities);
    expect(rows).toHaveLength(2);
    const rowA = rows.find((r) => r.domainId === domainA);
    const rowB = rows.find((r) => r.domainId === domainB);
    expect(rowA?.title).toBe("A");
    expect(rowA?.status).toBe("open");
    expect(rowB?.title).toBe("B-updated");
    expect(rowB?.status).toBe("closed");

    // Instance-scope upsert (domainId = NULL) on the same tuple must also
    // create its own row, not collide with A or B.
    const createdInstance = await registry.upsertEntity(pluginId, {
      domainId: null,
      entityType: "issue",
      scopeKind: "instance",
      scopeId: null,
      externalId: "ext-shared",
      title: "instance",
      status: "open",
      data: {},
    });
    expect(createdInstance?.id).toBeTruthy();
    expect(createdInstance?.id).not.toBe(createdA?.id);
    expect(createdInstance?.id).not.toBe(createdB?.id);

    const allRows = await db.select().from(pluginEntities);
    expect(allRows).toHaveLength(3);
  });

  it("pluginRegistryService.getEntityByExternalId scopes by domainId — never returns another tenant's row", async () => {
    const pluginId = await seedPlugin();
    const domainA = await seedDomain();
    const domainB = await seedDomain();

    const registry = pluginRegistryService(db);

    await registry.upsertEntity(pluginId, {
      domainId: domainA,
      entityType: "issue",
      scopeKind: "domain",
      scopeId: domainA,
      externalId: "ext-shared",
      title: "A",
      status: "open",
      data: {},
    });
    await registry.upsertEntity(pluginId, {
      domainId: domainB,
      entityType: "issue",
      scopeKind: "domain",
      scopeId: domainB,
      externalId: "ext-shared",
      title: "B",
      status: "open",
      data: {},
    });
    await registry.upsertEntity(pluginId, {
      domainId: null,
      entityType: "issue",
      scopeKind: "instance",
      scopeId: null,
      externalId: "ext-shared",
      title: "instance",
      status: "open",
      data: {},
    });

    const fromA = await registry.getEntityByExternalId(pluginId, "issue", "ext-shared", domainA);
    expect(fromA?.domainId).toBe(domainA);
    expect(fromA?.title).toBe("A");

    const fromB = await registry.getEntityByExternalId(pluginId, "issue", "ext-shared", domainB);
    expect(fromB?.domainId).toBe(domainB);
    expect(fromB?.title).toBe("B");

    const fromInstance = await registry.getEntityByExternalId(pluginId, "issue", "ext-shared", null);
    expect(fromInstance?.domainId).toBeNull();
    expect(fromInstance?.title).toBe("instance");

    // Unknown tenant returns null, not another tenant's row.
    const unknown = await registry.getEntityByExternalId(
      pluginId,
      "issue",
      "ext-shared",
      randomUUID(),
    );
    expect(unknown).toBeNull();
  });

  it("pluginRegistryService.createJobRun + createWebhookDelivery persist domainId so cascade delete reaps them", async () => {
    const pluginId = await seedPlugin();
    const domainA = await seedDomain();
    const domainB = await seedDomain();

    const registry = pluginRegistryService(db);
    const jobId = randomUUID();
    await db.insert(pluginJobs).values({
      id: jobId,
      pluginId,
      jobKey: "test-job",
      schedule: "* * * * *",
    });

    const runA = await registry.createJobRun(pluginId, jobId, "manual", domainA);
    const runB = await registry.createJobRun(pluginId, jobId, "manual", domainB);
    const runInstance = await registry.createJobRun(pluginId, jobId, "scheduled", null);

    expect(runA?.domainId).toBe(domainA);
    expect(runB?.domainId).toBe(domainB);
    expect(runInstance?.domainId).toBeNull();

    const whA = await registry.createWebhookDelivery(pluginId, "wh", domainA, {
      payload: { who: "A" },
    });
    const whB = await registry.createWebhookDelivery(pluginId, "wh", domainB, {
      payload: { who: "B" },
    });
    const whInstance = await registry.createWebhookDelivery(pluginId, "wh", null, {
      payload: { who: "instance" },
    });

    expect(whA?.domainId).toBe(domainA);
    expect(whB?.domainId).toBe(domainB);
    expect(whInstance?.domainId).toBeNull();

    // Cascade: deleting domain A reaps A's rows; B's and instance-scope rows stay.
    await db.delete(domains).where(eq(domains.id, domainA));

    const runs = await db.select().from(pluginJobRuns);
    expect(runs.map((r) => r.domainId).sort((a, b) => String(a).localeCompare(String(b)))).toEqual(
      [domainB, null].sort((a, b) => String(a).localeCompare(String(b))),
    );

    const deliveries = await db.select().from(pluginWebhookDeliveries);
    expect(
      deliveries.map((r) => r.domainId).sort((a, b) => String(a).localeCompare(String(b))),
    ).toEqual([domainB, null].sort((a, b) => String(a).localeCompare(String(b))));
  });

  it("buildHostServices.logger.log + flushPluginLogBuffer persist domainId so cascade delete reaps log rows", async () => {
    const pluginId = await seedPlugin();
    const domainA = await seedDomain();
    const domainB = await seedDomain();

    // Flush any leftovers from prior tests (the buffer is module-scoped).
    await flushPluginLogBuffer();
    await db.delete(pluginLogs);

    const services = buildHostServices(db, pluginId, "tenant-isolation-test", createEventBusStub());
    try {
      await services.logger.log({
        level: "info",
        message: "A log",
        domainId: domainA,
      });
      await services.logger.log({
        level: "warn",
        message: "B log",
        domainId: domainB,
      });
      await services.logger.log({
        level: "info",
        message: "instance log",
        // domainId omitted — explicit instance-scope.
      });
      await services.logger.log({
        level: "debug",
        message: "explicit-null log",
        domainId: null,
      });

      await flushPluginLogBuffer();

      const rows = await db
        .select()
        .from(pluginLogs)
        .where(eq(pluginLogs.pluginId, pluginId));
      const byMessage = new Map(rows.map((r) => [r.message, r]));
      expect(byMessage.get("A log")?.domainId).toBe(domainA);
      expect(byMessage.get("B log")?.domainId).toBe(domainB);
      expect(byMessage.get("instance log")?.domainId).toBeNull();
      expect(byMessage.get("explicit-null log")?.domainId).toBeNull();

      // Cascade: deleting domain A reaps A's log row; B's + NULL rows remain.
      await db.delete(domains).where(eq(domains.id, domainA));

      const afterDelete = await db
        .select()
        .from(pluginLogs)
        .where(eq(pluginLogs.pluginId, pluginId));
      const messages = afterDelete.map((r) => r.message).sort();
      expect(messages).toEqual(["B log", "explicit-null log", "instance log"]);
    } finally {
      services.dispose();
      // Ensure no leftover entries leak into other tests.
      await flushPluginLogBuffer();
    }
  });

  it("plugin_entities unique index treats NULL domainId as equal (NULLS NOT DISTINCT) so instance-scope dedup holds", async () => {
    const pluginId = await seedPlugin();

    // First instance-scope entity (domainId = NULL) — succeeds.
    await db.insert(pluginEntities).values({
      pluginId,
      domainId: null,
      entityType: "cron",
      scopeKind: "instance",
      scopeId: null,
      externalId: "global-cron-1",
    });

    // Second instance-scope row with the SAME (pluginId, entityType, externalId)
    // must be rejected. Without `.nullsNotDistinct()`, postgres would treat the
    // two NULL domain_ids as distinct and silently allow the duplicate.
    const err = await db
      .insert(pluginEntities)
      .values({
        pluginId,
        domainId: null,
        entityType: "cron",
        scopeKind: "instance",
        scopeId: null,
        externalId: "global-cron-1",
      })
      .then(
        () => null,
        (e: unknown) => e,
      );
    expect(err).toBeInstanceOf(Error);
    expect((err as { cause?: { code?: string } }).cause?.code).toBe("23505");
  });
});
