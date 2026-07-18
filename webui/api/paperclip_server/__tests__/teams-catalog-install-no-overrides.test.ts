import { randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { eq } from "drizzle-orm";
import { agents, domains, createDb } from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { teamsCatalogService } from "../services/teams-catalog.js";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe.sequential : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres teams catalog no-overrides install tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("teams catalog install with no caller adapter overrides", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;
  let tempHome: string | null = null;
  let oldPaperclipHome: string | undefined;

  beforeAll(async () => {
    oldPaperclipHome = process.env.PAPERCLIP_HOME;
    tempHome = await fs.mkdtemp(path.join(os.tmpdir(), "paperclip-teams-catalog-no-overrides-"));
    process.env.PAPERCLIP_HOME = tempHome;
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-teams-catalog-no-overrides-");
    db = createDb(tempDb.connectionString);
  }, 20_000);

  afterAll(async () => {
    if (oldPaperclipHome === undefined) delete process.env.PAPERCLIP_HOME;
    else process.env.PAPERCLIP_HOME = oldPaperclipHome;
    if (tempHome) await fs.rm(tempHome, { recursive: true, force: true });
    await tempDb?.cleanup();
  });

  async function seedEmptyDomain() {
    const domainId = randomUUID();
    await db.insert(domains).values({
      id: domainId,
      name: "Clean install domain",
      issuePrefix: `T${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });
    return domainId;
  }

  async function listAdapterTypesByName(domainId: string) {
    const rows = await db
      .select({
        name: agents.name,
        role: agents.role,
        adapterType: agents.adapterType,
        permissions: agents.permissions,
      })
      .from(agents)
      .where(eq(agents.domainId, domainId));
    return new Map(rows.map((row) => [row.name, row]));
  }

  it("installs core-exec-team end-to-end with no caller overrides and creates 3 claude_local agents", async () => {
    const domainId = await seedEmptyDomain();
    const svc = teamsCatalogService(db);

    await svc.installCatalogTeam(domainId, "core-exec-team", {
      collisionStrategy: "rename",
      include: { projects: false, issues: false },
    });

    const byName = await listAdapterTypesByName(domainId);
    expect(byName.size).toBe(3);

    const adapterTypes = Array.from(byName.values()).map((row) => row.adapterType);
    expect(adapterTypes).toEqual(["claude_local", "claude_local", "claude_local"]);
    expect(adapterTypes).not.toContain("process");
    expect(adapterTypes).not.toContain("http");
  });

  it("installs product-design end-to-end with no caller overrides and uses claude_local", async () => {
    const domainId = await seedEmptyDomain();
    const svc = teamsCatalogService(db);

    await svc.installCatalogTeam(domainId, "product-design", {
      collisionStrategy: "rename",
      include: { projects: false, issues: false },
    });

    const byName = await listAdapterTypesByName(domainId);
    expect(byName.size).toBe(1);
    const adapterTypes = Array.from(byName.values()).map((row) => row.adapterType);
    expect(adapterTypes).toEqual(["claude_local"]);
    expect(adapterTypes).not.toContain("process");
  });

  it("installs product-engineering end-to-end with no caller overrides and uses claude_local for every agent", async () => {
    const domainId = await seedEmptyDomain();
    const svc = teamsCatalogService(db);

    await svc.installCatalogTeam(domainId, "product-engineering", {
      collisionStrategy: "rename",
      include: { projects: false, issues: false },
    });

    const byName = await listAdapterTypesByName(domainId);
    expect(byName.size).toBe(3);
    const adapterTypes = Array.from(byName.values()).map((row) => row.adapterType);
    expect(adapterTypes).toEqual(["claude_local", "claude_local", "claude_local"]);
    expect(adapterTypes).not.toContain("process");
    expect(byName.get("CTO")?.permissions).toMatchObject({ canCreateAgents: true });
  });

  it("honors an explicit caller adapter override for a single slug while defaulting the rest to claude_local", async () => {
    const domainId = await seedEmptyDomain();
    const svc = teamsCatalogService(db);

    await svc.installCatalogTeam(domainId, "core-exec-team", {
      collisionStrategy: "rename",
      include: { projects: false, issues: false },
      adapterOverrides: {
        cto: { adapterType: "opencode_local", adapterConfig: { model: "anthropic/claude-opus-4" } },
      },
    });

    const byName = await listAdapterTypesByName(domainId);
    expect(byName.size).toBe(3);
    const ctoRow = Array.from(byName.values()).find((row) => row.role === "engineering-manager" || row.name === "CTO");
    expect(ctoRow?.adapterType).toBe("opencode_local");
    const otherAdapters = Array.from(byName.values())
      .filter((row) => row !== ctoRow)
      .map((row) => row.adapterType);
    expect(otherAdapters).toEqual(["claude_local", "claude_local"]);
  });
});
