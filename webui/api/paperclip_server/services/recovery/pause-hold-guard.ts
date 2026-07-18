import type { Db } from "@paperclipai/db";
import { issueTreeControlService } from "../issue-tree-control.js";

type IssueTreeControlService = ReturnType<typeof issueTreeControlService>;

export async function isAutomaticRecoverySuppressedByPauseHold(
  db: Db,
  domainId: string,
  issueId: string,
  treeControlSvc: IssueTreeControlService = issueTreeControlService(db),
) {
  const activePauseHold = await treeControlSvc.getActivePauseHoldGate(domainId, issueId);
  return Boolean(activePauseHold);
}
