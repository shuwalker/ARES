import { randomUUID } from "node:crypto";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { and, eq } from "drizzle-orm";
import {
  agents,
  domains,
  domainSecretBindings,
  domainSecrets,
  createDb,
  environmentCustomImageSetupSessions,
  environmentLeases,
  environments,
  executionWorkspaces,
  heartbeatRuns,
  instanceSettings,
  issues,
  projects,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { environmentService } from "../services/environments.ts";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres environment service tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("environmentService leases", () => {
  let stopDb: (() => Promise<void>) | null = null;
  let db!: ReturnType<typeof createDb>;
  let svc!: ReturnType<typeof environmentService>;

  beforeAll(async () => {
    const started = await startEmbeddedPostgresTestDatabase("environment-service");
    stopDb = started.stop;
    db = createDb(started.connectionString);
    svc = environmentService(db);
  });

  afterEach(async () => {
    await db.delete(domainSecretBindings);
    await db.delete(environmentCustomImageSetupSessions);
    await db.delete(environmentLeases);
    await db.delete(heartbeatRuns);
    await db.delete(issues);
    await db.delete(executionWorkspaces);
    await db.delete(projects);
    await db.delete(agents);
    await db.delete(instanceSettings);
    await db.delete(environments);
    await db.delete(domainSecrets);
    await db.delete(domains);
  });

  afterAll(async () => {
    await stopDb?.();
  });

  async function seedEnvironment() {
    const domainId = randomUUID();
    const agentId = randomUUID();
    const environmentId = randomUUID();
    const runId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.insert(agents).values({
      id: agentId,
      domainId,
      name: "CodexCoder",
      role: "engineer",
      status: "active",
      adapterType: "codex_local",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.insert(environments).values({
      id: environmentId,
      name: "Lease Fixture",
      driver: "ssh",
      status: "active",
      config: {
        host: "fixture.example.test",
        port: 22,
        username: "fixture",
        remoteWorkspacePath: "/srv/paperclip",
      },
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await db.insert(heartbeatRuns).values({
      id: runId,
      domainId,
      agentId,
      invocationSource: "manual",
      status: "running",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    return { domainId, agentId, environmentId, runId };
  }

  it("acquires and releases a lease for a run", async () => {
    const { domainId, environmentId, runId } = await seedEnvironment();

    const lease = await svc.acquireLease({
      domainId,
      environmentId,
      heartbeatRunId: runId,
      metadata: { driver: "local" },
    });

    expect(lease.status).toBe("active");
    expect(lease.heartbeatRunId).toBe(runId);

    const released = await svc.releaseLease(lease.id);

    expect(released?.status).toBe("released");
    expect(released?.releasedAt).not.toBeNull();
  });

  it("releases all active leases for a run without touching unrelated rows", async () => {
    const { domainId, agentId, environmentId, runId } = await seedEnvironment();
    const otherRunId = randomUUID();

    await db.insert(heartbeatRuns).values({
      id: otherRunId,
      domainId,
      agentId,
      invocationSource: "manual",
      status: "running",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const targetLease = await svc.acquireLease({
      domainId,
      environmentId,
      heartbeatRunId: runId,
    });
    const otherLease = await svc.acquireLease({
      domainId,
      environmentId,
      heartbeatRunId: otherRunId,
    });

    const released = await svc.releaseLeasesForRun(runId);

    expect(released.map((lease) => lease.id)).toEqual([targetLease.id]);

    const stillActive = await svc.listLeases(environmentId, { status: "active" });
    expect(stillActive.map((lease) => lease.id)).toEqual([otherLease.id]);
  });

  it("aggregates delete blast radius counts into static and active tiers", async () => {
    const domainId = randomUUID();
    const otherDomainId = randomUUID();
    const environmentId = randomUUID();
    const otherEnvironmentId = randomUUID();
    const projectId = randomUUID();
    const issueId = randomUUID();
    const workspaceId = randomUUID();
    const secretId = randomUUID();
    const otherSecretId = randomUUID();
    const now = new Date();

    await db.insert(domains).values([
      {
        id: domainId,
        name: "Acme",
        status: "active",
        issuePrefix: "ACM",
        createdAt: now,
        updatedAt: now,
      },
      {
        id: otherDomainId,
        name: "Other Co",
        status: "active",
        issuePrefix: "OTH",
        createdAt: now,
        updatedAt: now,
      },
    ]);
    await db.insert(environments).values([
      {
        id: environmentId,
        name: "Shared SSH",
        driver: "ssh",
        status: "active",
        config: {
          host: "fixture.example.test",
          port: 22,
          username: "fixture",
          remoteWorkspacePath: "/srv/paperclip",
        },
        createdAt: now,
        updatedAt: now,
      },
      {
        id: otherEnvironmentId,
        name: "Other SSH",
        driver: "ssh",
        status: "active",
        config: {
          host: "other.example.test",
          port: 22,
          username: "fixture",
          remoteWorkspacePath: "/srv/paperclip",
        },
        createdAt: now,
        updatedAt: now,
      },
    ]);
    await db.insert(instanceSettings).values({
      singletonKey: "default",
      defaultEnvironmentId: environmentId,
      general: {},
      experimental: {},
      createdAt: now,
      updatedAt: now,
    });
    await db.insert(agents).values([
      {
        domainId,
        name: "CodexCoder",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        defaultEnvironmentId: environmentId,
        permissions: {},
        createdAt: now,
        updatedAt: now,
      },
      {
        domainId,
        name: "OtherCoder",
        role: "engineer",
        status: "active",
        adapterType: "codex_local",
        adapterConfig: {},
        runtimeConfig: {},
        defaultEnvironmentId: otherEnvironmentId,
        permissions: {},
        createdAt: now,
        updatedAt: now,
      },
    ]);
    await db.insert(projects).values({
      id: projectId,
      domainId,
      name: "Project",
      status: "in_progress",
      executionWorkspacePolicy: {
        enabled: true,
        defaultMode: "isolated_workspace",
        environmentId,
      },
      createdAt: now,
      updatedAt: now,
    });
    await db.insert(issues).values({
      id: issueId,
      domainId,
      projectId,
      title: "Issue",
      status: "todo",
      priority: "medium",
      executionWorkspaceSettings: {
        mode: "isolated_workspace",
        environmentId,
      },
      createdAt: now,
      updatedAt: now,
    });
    await db.insert(executionWorkspaces).values({
      id: workspaceId,
      domainId,
      projectId,
      sourceIssueId: issueId,
      mode: "isolated_workspace",
      strategyType: "git_worktree",
      name: "Workspace",
      status: "active",
      providerType: "git_worktree",
      metadata: {
        config: {
          environmentId,
        },
      },
      createdAt: now,
      updatedAt: now,
    });
    await db.insert(domainSecrets).values([
      {
        id: secretId,
        domainId,
        key: "env-secret",
        name: "Env Secret",
        provider: "local_encrypted",
        createdAt: now,
        updatedAt: now,
      },
      {
        id: otherSecretId,
        domainId: otherDomainId,
        key: "other-env-secret",
        name: "Other Env Secret",
        provider: "local_encrypted",
        createdAt: now,
        updatedAt: now,
      },
    ]);
    await db.insert(domainSecretBindings).values([
      {
        domainId,
        secretId,
        targetType: "environment",
        targetId: environmentId,
        configPath: "env.OPENAI_API_KEY",
        createdAt: now,
        updatedAt: now,
      },
      {
        domainId: otherDomainId,
        secretId: otherSecretId,
        targetType: "environment",
        targetId: environmentId,
        configPath: "env.ANTHROPIC_API_KEY",
        createdAt: now,
        updatedAt: now,
      },
      {
        domainId,
        secretId,
        targetType: "agent",
        targetId: "agent-1",
        configPath: "env.OPENAI_API_KEY",
        createdAt: now,
        updatedAt: now,
      },
    ]);
    await svc.acquireLease({
      domainId,
      environmentId,
    });
    const releasedLease = await svc.acquireLease({
      domainId,
      environmentId,
    });
    await svc.releaseLease(releasedLease.id);
    await db.insert(environmentCustomImageSetupSessions).values([
      {
        environmentId,
        provider: "fake-plugin",
        status: "waiting_for_user",
        createdAt: now,
        updatedAt: now,
      },
    ]);

    const impact = await svc.getDeleteBlastRadius(environmentId);

    expect(impact).toEqual({
      environmentId,
      canDelete: false,
      deleteBlockedReasons: ["instance_default"],
      staticReferences: {
        isManagedLocal: false,
        isInstanceDefault: true,
        agentDefaultCount: 1,
        executionWorkspaceSelectionCount: 1,
        issueSelectionCount: 1,
        projectSelectionCount: 1,
        secretBindingCount: 2,
      },
      activeRuntimeUse: {
        activeLeaseCount: 1,
        activeCustomImageSetupSessionCount: 1,
        hasActiveRuntimeUse: true,
      },
    });
  });

  it("guards removeIfDeletable with atomic local/default predicates", async () => {
    const localEnvId = randomUUID();
    const defaultEnvId = randomUUID();
    const deletableEnvId = randomUUID();
    const now = new Date();

    await db.insert(environments).values([
      {
        id: localEnvId,
        name: "Local Guard",
        driver: "local",
        status: "active",
        config: {},
        createdAt: now,
        updatedAt: now,
      },
      {
        id: defaultEnvId,
        name: "Default SSH Guard",
        driver: "ssh",
        status: "active",
        config: {
          host: "default.example.test",
          port: 22,
          username: "fixture",
          remoteWorkspacePath: "/srv/paperclip",
        },
        createdAt: now,
        updatedAt: now,
      },
      {
        id: deletableEnvId,
        name: "Deletable SSH Guard",
        driver: "ssh",
        status: "active",
        config: {
          host: "delete.example.test",
          port: 22,
          username: "fixture",
          remoteWorkspacePath: "/srv/paperclip",
        },
        createdAt: now,
        updatedAt: now,
      },
    ]);
    await db.insert(instanceSettings).values({
      singletonKey: "default",
      defaultEnvironmentId: defaultEnvId,
      general: {},
      experimental: {},
      createdAt: now,
      updatedAt: now,
    });

    const removedLocal = await svc.removeIfDeletable(localEnvId);
    const localRows = await db.select().from(environments).where(eq(environments.id, localEnvId));

    expect(removedLocal).toBeNull();
    expect(localRows).toHaveLength(1);
    expect(localRows[0]?.driver).toBe("local");

    const removedDefault = await svc.removeIfDeletable(defaultEnvId);
    const defaultRows = await db.select().from(environments).where(eq(environments.id, defaultEnvId));

    expect(removedDefault).toBeNull();
    expect(defaultRows).toHaveLength(1);

    const removedDeletable = await svc.removeIfDeletable(deletableEnvId);
    const deletedRows = await db.select().from(environments).where(eq(environments.id, deletableEnvId));

    expect(removedDeletable?.id).toBe(deletableEnvId);
    expect(deletedRows).toHaveLength(0);
  });

  it("creates and then reuses the default local environment for a domain", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const created = await svc.ensureLocalEnvironment(domainId);
    const reused = await svc.ensureLocalEnvironment(domainId);

    expect(created.driver).toBe("local");
    expect(reused.id).toBe(created.id);

    const rows = await db.select().from(environments).where(eq(environments.driver, "local"));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.name).toBe("Local");
  });

  it("leaves an existing default local environment untouched", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    const archivedAt = new Date("2025-01-01T00:00:00.000Z");
    const [existing] = await db
      .insert(environments)
      .values({
        name: "Archived Local",
        description: "Operator-managed local environment",
        driver: "local",
        status: "archived",
        config: { shell: "zsh" },
        metadata: { owner: "operator" },
        createdAt: archivedAt,
        updatedAt: archivedAt,
      })
      .returning();

    const ensured = await svc.ensureLocalEnvironment(domainId);

    expect(ensured.id).toBe(existing?.id);
    expect(ensured.name).toBe("Archived Local");
    expect(ensured.status).toBe("archived");
    expect(ensured.metadata).toEqual({ owner: "operator" });

    const rows = await db.select().from(environments).where(eq(environments.driver, "local"));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.updatedAt.toISOString()).toBe(archivedAt.toISOString());
  });

  it("deduplicates concurrent default local environment creation", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const results = await Promise.all(
      Array.from({ length: 8 }, () => svc.ensureLocalEnvironment(domainId)),
    );

    expect(new Set(results.map((environment) => environment.id)).size).toBe(1);

    const rows = await db.select().from(environments).where(eq(environments.driver, "local"));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.driver).toBe("local");
    expect(rows[0]?.status).toBe("active");
  });

  it("ensures, refreshes, and finds a managed Kubernetes sandbox environment", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    // No managed k8s env yet.
    expect(await svc.findKubernetesEnvironment(domainId)).toBeNull();

    const created = await svc.ensureKubernetesEnvironment(domainId, {
      backend: "job",
      inCluster: true,
      runtimeClassName: "gvisor",
      egressMode: "cilium",
      egressAllowFqdns: ["api.anthropic.com"],
    });

    expect(created.driver).toBe("sandbox");
    expect(created.config.provider).toBe("kubernetes");
    expect(created.config.backend).toBe("job");
    expect(created.config.runtimeClassName).toBe("gvisor");
    expect(created.metadata?.managedKubernetesSandbox).toBe(true);

    // Idempotent: second call refreshes config in place, no new row.
    const refreshed = await svc.ensureKubernetesEnvironment(domainId, {
      backend: "job",
      inCluster: true,
      egressMode: "cilium",
      egressAllowFqdns: ["api.anthropic.com", "api.openai.com"],
    });
    expect(refreshed.id).toBe(created.id);
    expect(refreshed.config.egressAllowFqdns).toEqual([
      "api.anthropic.com",
      "api.openai.com",
    ]);

    const found = await svc.findKubernetesEnvironment(domainId);
    expect(found?.id).toBe(created.id);

    const rows = await db
      .select()
      .from(environments)
      .where(eq(environments.driver, "sandbox"));
    expect(rows.filter((row) => row.driver === "sandbox")).toHaveLength(1);
  });

  it("deduplicates concurrent managed Kubernetes environment creation", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    // No partial unique index covers sandbox drivers yet, so dedup is
    // post-insert convergence (prefer the oldest row, delete the loser).
    const results = await Promise.all(
      Array.from({ length: 8 }, () =>
        svc.ensureKubernetesEnvironment(domainId, { inCluster: true, backend: "job" }),
      ),
    );

    expect(new Set(results.map((environment) => environment.id)).size).toBe(1);

    const rows = await db
      .select()
      .from(environments)
      .where(eq(environments.driver, "sandbox"));
    expect(rows).toHaveLength(1);
    expect((rows[0]?.metadata as Record<string, unknown>)?.managedKubernetesSandbox).toBe(true);
  });

  it("returns a conflict when creating a second environment with the same name", async () => {
    await seedEnvironment();

    await svc.create({
      name: "Shared Fixture",
      driver: "ssh",
      status: "active",
      config: {
        host: "fixture.example.test",
        port: 22,
        username: "fixture",
        remoteWorkspacePath: "/srv/paperclip",
      },
    });

    await expect(svc.create({
      name: "Shared Fixture",
      driver: "sandbox",
      status: "active",
      config: {
        provider: "fake-plugin",
        image: "fake:test",
        reuseLease: false,
      },
    })).rejects.toMatchObject({
      status: 409,
      message: 'An environment named "Shared Fixture" already exists for this instance.',
    });
  });

  it("returns a conflict when renaming an environment to an existing name", async () => {
    const { environmentId } = await seedEnvironment();
    const otherEnvironmentId = randomUUID();
    const now = new Date();

    await db.insert(environments).values({
      id: otherEnvironmentId,
      name: "Other Fixture",
      driver: "sandbox",
      status: "active",
      config: {
        provider: "fake-plugin",
        image: "fake:test",
        reuseLease: false,
      },
      createdAt: now,
      updatedAt: now,
    });

    await expect(svc.update(otherEnvironmentId, {
      name: "Lease Fixture",
    })).rejects.toMatchObject({
      status: 409,
      message: 'An environment named "Lease Fixture" already exists for this instance.',
    });

    const original = await svc.getById(environmentId);
    expect(original?.name).toBe("Lease Fixture");
  });

  it("rejects a second managed-sandbox row for the same domain at the DB level", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const now = new Date();
    await db.insert(environments).values({
      name: "First",
      driver: "sandbox",
      status: "active",
      config: { provider: "kubernetes" },
      metadata: { managedByPaperclip: true, managedKubernetesSandbox: true },
      createdAt: now,
      updatedAt: now,
    });

    // Partial unique index environments_domain_managed_sandbox_idx rejects a
    // second row matching driver='sandbox' AND managedByPaperclip=true for the
    // same domain. This is the DB-level invariant that replaced the previous
    // application-side post-insert convergence loop.
    const secondInsert = db.insert(environments).values({
      name: "Second",
      driver: "sandbox",
      status: "active",
      config: { provider: "kubernetes" },
      metadata: { managedByPaperclip: true, managedKubernetesSandbox: true },
      createdAt: new Date(now.getTime() + 1),
      updatedAt: new Date(now.getTime() + 1),
    });
    let raisedConstraint: string | null = null;
    try {
      await secondInsert;
    } catch (error) {
      raisedConstraint =
        (error as { constraint_name?: string; cause?: { constraint_name?: string } })
          ?.constraint_name ??
        (error as { cause?: { constraint_name?: string } })?.cause?.constraint_name ??
        "unknown";
    }
    expect(raisedConstraint).toBe("environments_managed_sandbox_idx");

    // Index does NOT cover tenant-created sandbox rows (no managedByPaperclip
    // marker) — operators must be able to keep multiple tenant sandbox envs.
    await db.insert(environments).values({
      name: "Tenant Sandbox",
      driver: "sandbox",
      status: "active",
      config: { provider: "fake" },
      metadata: { tenant: true },
      createdAt: new Date(now.getTime() + 2),
      updatedAt: new Date(now.getTime() + 2),
    });

    const rows = await db
      .select()
      .from(environments)
      .where(eq(environments.driver, "sandbox"));
    expect(rows).toHaveLength(2);
  });

  it("does not treat a non-kubernetes sandbox environment as the managed k8s env", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });
    await svc.create(domainId, {
      name: "Fake Sandbox",
      driver: "sandbox",
      config: { provider: "fake", image: "busybox", reuseLease: false },
    });

    expect(await svc.findKubernetesEnvironment(domainId)).toBeNull();
  });

  it("ignores a config.provider=kubernetes sandbox env without the managed marker", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    // A tenant-created sandbox env with config.provider "kubernetes" but WITHOUT
    // the managed metadata marker must NOT be treated as the managed k8s env,
    // otherwise it would bypass the operator gVisor runtimeClass / Cilium egress.
    await svc.create(domainId, {
      name: "Tenant K8s Sandbox",
      driver: "sandbox",
      config: { provider: "kubernetes", reuseLease: false },
    });

    expect(await svc.findKubernetesEnvironment(domainId)).toBeNull();

    // The managed env (created via ensureKubernetesEnvironment) carries the
    // marker and is the only one found.
    const managed = await svc.ensureKubernetesEnvironment(domainId, {
      backend: "job",
      inCluster: true,
      runtimeClassName: "gvisor",
    });
    const found = await svc.findKubernetesEnvironment(domainId);
    expect(found?.id).toBe(managed.id);
  });

  it("allows multiple SSH environments for the same domain", async () => {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Acme",
      status: "active",
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const first = await svc.create(domainId, {
      name: "Production SSH",
      driver: "ssh",
      config: { host: "prod.example.com", username: "deploy" },
    });
    const second = await svc.create(domainId, {
      name: "Staging SSH",
      driver: "ssh",
      config: { host: "staging.example.com", username: "deploy" },
    });

    expect(first.id).not.toBe(second.id);

    const rows = await db.select().from(environments);
    expect(rows.filter((row) => row.driver === "ssh")).toHaveLength(2);
  });
});
