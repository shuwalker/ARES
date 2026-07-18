import { randomUUID } from "node:crypto";
import { sql } from "drizzle-orm";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import {
  domains,
  createDb,
  documents,
  issueComments,
  issueDocuments,
  issueReferenceMentions,
  issues,
} from "@paperclipai/db";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";
import { issueReferenceService } from "../services/issue-references.ts";

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

async function ensureIssueReferenceMentionsTable(db: ReturnType<typeof createDb>) {
  await db.execute(sql.raw(`
    CREATE TABLE IF NOT EXISTS "issue_reference_mentions" (
      "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      "domain_id" uuid NOT NULL,
      "source_issue_id" uuid NOT NULL REFERENCES "issues"("id") ON DELETE CASCADE,
      "target_issue_id" uuid NOT NULL REFERENCES "issues"("id") ON DELETE CASCADE,
      "source_kind" text NOT NULL,
      "source_record_id" uuid,
      "document_key" text,
      "matched_text" text,
      "created_at" timestamptz NOT NULL DEFAULT now(),
      "updated_at" timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS "issue_reference_mentions_domain_source_issue_idx"
      ON "issue_reference_mentions" ("domain_id", "source_issue_id");
    CREATE INDEX IF NOT EXISTS "issue_reference_mentions_domain_target_issue_idx"
      ON "issue_reference_mentions" ("domain_id", "target_issue_id");
    CREATE INDEX IF NOT EXISTS "issue_reference_mentions_domain_issue_pair_idx"
      ON "issue_reference_mentions" ("domain_id", "source_issue_id", "target_issue_id");
    CREATE UNIQUE INDEX IF NOT EXISTS "issue_reference_mentions_domain_source_mention_uq"
      ON "issue_reference_mentions" ("domain_id", "source_issue_id", "target_issue_id", "source_kind", "source_record_id");
  `));
}

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres issue reference tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("issueReferenceService", () => {
  let db!: ReturnType<typeof createDb>;
  let refs!: ReturnType<typeof issueReferenceService>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;

  beforeAll(async () => {
    tempDb = await startEmbeddedPostgresTestDatabase("paperclip-issue-refs-");
    db = createDb(tempDb.connectionString);
    refs = issueReferenceService(db);
    await ensureIssueReferenceMentionsTable(db);
  }, 20_000);

  afterEach(async () => {
    await db.delete(issueReferenceMentions);
    await db.delete(issueComments);
    await db.delete(issueDocuments);
    await db.delete(documents);
    await db.delete(issues);
    await db.delete(domains);
  });

  afterAll(async () => {
    await tempDb?.cleanup();
  });

  it("tracks outbound and inbound references across issue fields, comments, and documents", async () => {
    const domainId = randomUUID();
    const sourceIssueId = randomUUID();
    const targetTwoId = randomUUID();
    const targetThreeId = randomUUID();
    const inboundIssueId = randomUUID();
    const commentId = randomUUID();
    const documentId = randomUUID();
    const issueDocumentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip",
      issuePrefix: `R${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(issues).values([
      {
        id: sourceIssueId,
        domainId,
        title: "Coordinate PAP-2",
        description: "Review /issues/pap-3 and ignore PAP-1 self references.",
        status: "todo",
        priority: "medium",
        identifier: "PAP-1",
      },
      {
        id: targetTwoId,
        domainId,
        title: "Target two",
        status: "todo",
        priority: "medium",
        identifier: "PAP-2",
      },
      {
        id: targetThreeId,
        domainId,
        title: "Target three",
        status: "todo",
        priority: "medium",
        identifier: "PAP-3",
      },
      {
        id: inboundIssueId,
        domainId,
        title: "Inbound reference",
        description: "This one depends on PAP-1.",
        status: "in_progress",
        priority: "high",
        identifier: "PAP-4",
      },
    ]);

    await refs.syncIssue(sourceIssueId);
    await refs.syncIssue(inboundIssueId);

    await db.insert(issueComments).values({
      id: commentId,
      domainId,
      issueId: sourceIssueId,
      body: "Follow up in https://paperclip.test/issues/pap-2 after the document lands.",
    });
    await refs.syncComment(commentId);

    await db.insert(documents).values({
      id: documentId,
      domainId,
      title: "Plan",
      format: "markdown",
      latestBody: "Spec note: /PAP/issues/PAP-3",
      latestRevisionNumber: 1,
    });
    await db.insert(issueDocuments).values({
      id: issueDocumentId,
      domainId,
      issueId: sourceIssueId,
      documentId,
      key: "plan",
    });
    await refs.syncDocument(documentId);

    const summary = await refs.listIssueReferenceSummary(sourceIssueId);

    expect(summary.outbound.map((item) => item.issue.identifier)).toEqual(["PAP-2", "PAP-3"]);
    expect(summary.outbound[0]?.mentionCount).toBe(2);
    expect(summary.outbound[0]?.sources.map((source) => source.label)).toEqual(["title", "comment"]);
    expect(summary.outbound[1]?.mentionCount).toBe(2);
    expect(summary.outbound[1]?.sources.map((source) => source.label)).toEqual(["description", "plan"]);
    expect(summary.inbound.map((item) => item.issue.identifier)).toEqual(["PAP-4"]);

    await refs.deleteDocumentSource(documentId);

    const withoutDocument = await refs.listIssueReferenceSummary(sourceIssueId);
    const pap3 = withoutDocument.outbound.find((item) => item.issue.identifier === "PAP-3");

    expect(pap3?.mentionCount).toBe(1);
    expect(pap3?.sources.map((source) => source.label)).toEqual(["description"]);
  });

  it("backfills existing references for a domain without requiring write-time sync", async () => {
    const domainId = randomUUID();
    const sourceIssueId = randomUUID();
    const targetIssueId = randomUUID();
    const commentId = randomUUID();
    const documentId = randomUUID();
    const issueDocumentId = randomUUID();

    await db.insert(domains).values({
      id: domainId,
      name: "Paperclip Backfill",
      issuePrefix: `B${domainId.replace(/-/g, "").slice(0, 6).toUpperLifeAdmin()}`,
      requireBoardApprovalForNewAgents: false,
    });

    await db.insert(issues).values([
      {
        id: sourceIssueId,
        domainId,
        title: "Legacy issue",
        status: "todo",
        priority: "medium",
        identifier: "PAP-10",
      },
      {
        id: targetIssueId,
        domainId,
        title: "Referenced legacy issue",
        status: "todo",
        priority: "medium",
        identifier: "PAP-20",
      },
    ]);

    await db.insert(issueComments).values({
      id: commentId,
      domainId,
      issueId: sourceIssueId,
      body: "Legacy comment points at PAP-20.",
    });

    await db.insert(documents).values({
      id: documentId,
      domainId,
      title: "Legacy plan",
      format: "markdown",
      latestBody: "Legacy plan also links /issues/PAP-20.",
      latestRevisionNumber: 1,
    });
    await db.insert(issueDocuments).values({
      id: issueDocumentId,
      domainId,
      issueId: sourceIssueId,
      documentId,
      key: "plan",
    });

    await refs.syncAllForDomain(domainId);

    const summary = await refs.listIssueReferenceSummary(sourceIssueId);

    expect(summary.outbound).toHaveLength(1);
    expect(summary.outbound[0]?.issue.identifier).toBe("PAP-20");
    expect(summary.outbound[0]?.mentionCount).toBe(2);
    expect(summary.outbound[0]?.sources.map((source) => source.label)).toEqual(["plan", "comment"]);
  });
});
