# Video Production Workflow Recipe

Build a reusable episode workflow for technical YouTube channels.

The goal is to turn messy build work into a package another person can film, edit, audit, or continue.

## Problem

Technical videos fail when the work lives only in the builder's head.

A usable workflow must preserve the build proof, the story, the assets, and the release checklist in plain files.

## Folder contract

Use one folder per episode or project:

```text
Episode - Title/
├── 01_Production-Assets/
├── 02_WorkInProgress/
├── 03_Project-Notes/
├── 04_Engineering-Work/
└── 05_Deliverables/
```

## What each folder is for

### 01_Production-Assets

Audience-facing assets:

- script;
- talking points;
- shot list;
- thumbnail notes;
- B-roll checklist;
- graphics prompts;
- music/SFX notes.

### 02_WorkInProgress

Drafts and rough cuts:

- messy outlines;
- alternate intros;
- editing notes;
- scratch renders;
- temporary review exports.

### 03_Project-Notes

Research and decisions:

- references;
- competitive notes;
- decisions made;
- risks;
- blockers;
- open questions.

### 04_Engineering-Work

Proof that the episode claim is real:

- source code;
- demo scripts;
- test logs;
- setup instructions;
- hardware checks;
- benchmark outputs.

### 05_Deliverables

The clean package:

- final script;
- final demo instructions;
- release notes;
- viewer kit;
- public-safe docs;
- final checklist.

## Operating loop

### 1. Capture the raw idea

Write the first rough note without forcing structure.

Minimum fields:

```markdown
# Idea

## Promise
What will the viewer be able to understand, build, or try?

## Proof
What real thing must work on camera?

## Viewer takeaway
What can someone copy after watching?
```

### 2. Convert idea into episode assets

Create:

- one sentence premise;
- demo proof checklist;
- rough script;
- B-roll list;
- risk list.

### 3. Build the proof before polishing the story

If the episode promises software, run it.

If it promises hardware, test the hardware path.

If it promises a workflow, execute the workflow end to end.

Do not call an episode film-ready from a plan alone.

### 4. Package for another operator

Every episode should pass this handoff test:

> Could another editor, assistant, or builder open the folder and know what to do next?

If not, add the missing instruction file.

## Production state model

```json
{
  "episode": "Episode - Title",
  "state": "seed|building|ready_to_rehearse|ready_to_film|post_production|ready_to_publish",
  "proof_status": "untested|partial|verified|blocked",
  "assets": {
    "script": "missing|draft|final",
    "shot_list": "missing|draft|final",
    "demo": "missing|dry_run_ok|live_ok",
    "viewer_kit": "missing|draft|public_safe"
  },
  "blockers": [],
  "next_action": ""
}
```

## Verification gates

### Ready to rehearse

- Script or talking points exist.
- Demo has at least a dry-run path.
- B-roll checklist exists.
- Known blockers are written down.

### Ready to film

- Demo was executed successfully.
- Hardware or service dependencies were checked.
- The script matches what the demo actually does.
- No dead app tabs, missing files, or fake claims remain.
- Public-safe viewer materials are separated from private runtime files.

### Ready to publish

- Final export exists.
- Title and description draft exist.
- Thumbnail or thumbnail brief exists.
- Links and credits are checked.
- Public repo/docs contain only sanitized deliverables.

## Automation opportunities

Safe to automate:

- folder creation;
- checklist generation;
- transcript extraction from rough recordings;
- asset inventory;
- build/test log capture;
- public-path and secret scanning;
- release checklist reports.

Requires human approval:

- publishing;
- deleting source footage;
- committing public repo changes;
- claiming a hardware demo worked without live proof;
- moving finished archives to long-term storage.

## Reusable checklist

```markdown
# Episode Checklist

## Premise
- [ ] One-sentence viewer promise
- [ ] Why it matters now
- [ ] What the viewer can copy

## Proof
- [ ] Demo command or runbook
- [ ] Test output saved
- [ ] Hardware/service status checked
- [ ] Failure path documented

## Production assets
- [ ] Script or talking points
- [ ] Shot list
- [ ] B-roll list
- [ ] Thumbnail direction
- [ ] Music/SFX notes

## Handoff
- [ ] Folder uses the 5-folder contract
- [ ] No private secrets or local-only paths in public deliverables
- [ ] Next action is obvious
- [ ] Release/readiness state is accurate
```

## Key rule

Do not say “done” when the folder is only organized.

Use precise states:

- production-packaged;
- ready to rehearse;
- ready to film;
- post-production;
- ready to publish.

Each state needs proof.
