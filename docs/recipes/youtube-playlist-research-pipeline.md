# YouTube Playlist Research Pipeline Recipe

Build a pipeline that turns a YouTube playlist into reproducible research notes.

The goal is not summarization. The goal is: “Could I rebuild what this video showed?”

## Problem

Research playlists grow faster than humans can process them.

A healthy pipeline must drain the queue in small verified batches, not just fetch transcripts forever.

## Inputs

- A YouTube playlist ID.
- A YouTube Data API key for read-only playlist metadata.
- A transcript source, usually `yt-dlp` subtitles first and Whisper fallback second.
- An LLM endpoint for structured extraction.
- A knowledge-base folder or database for output notes.
- A processed ledger, for example `processed_ids.json`.
- An optional removal queue for videos that are safely processed.

## Outputs

For every processed video, write one durable note with these sections:

```markdown
# Video Title

## Reproducible Outcome
What the video built, demonstrated, or taught.

## Software Stack
Apps, libraries, models, plugins, services, operating systems, hardware, APIs, datasets, and versions.

## Reproduction Recipe
Commands, setup steps, config files, prompts, assets, runtime order, and validation.

## Ares Reproduction Status
yes | partial | no | unknown — with the exact reason.

## Missing Requirements
Credentials, hardware, datasets, visual details, code, or manual steps still missing.

## Next Actions
3-7 executable steps to reproduce or test it.

## Visual / Manual Review Needed
What the transcript cannot prove.
```

## Minimum state model

```json
{
  "phase": "transcript_partial",
  "timestamp": "2026-06-06T00:00:00",
  "counts": {
    "results": 0,
    "transcripts": 0,
    "analysis": 0,
    "kb_saved": 0,
    "pending_transcripts": 0,
    "pending_analysis": 0,
    "pending_save": 0
  },
  "results": [
    {
      "meta": {
        "video_id": "...",
        "title": "...",
        "channel": "...",
        "url": "...",
        "playlist_item_id": "..."
      },
      "transcript": "",
      "transcript_source": "yt-dlp|whisper|",
      "transcript_error": "",
      "analysis": {},
      "kb_saved": false
    }
  ]
}
```

## Golden path

### 1. Catalog and reconcile

Fetch live playlist items through the YouTube API.

Compare the live count against local state.

If the playlist has more videos than local state, append new rows instead of overwriting progress.

### 2. Fetch transcripts in bounded batches

Process a small number of pending transcript rows per run.

Checkpoint after each video.

A timeout should lose at most one in-flight video.

### 3. Analyze in bounded batches

Analyze only videos that already have transcripts and do not already have analysis.

Use a small analysis batch size, because each video may require multiple LLM calls.

Checkpoint after each analyzed video.

### 4. Save only completed rows

Save rows where transcript and analysis exist and `kb_saved` is false.

Update the processed ledger only after the output note exists.

### 5. Queue removal separately

Queueing a video for removal is not deletion.

Do not claim the playlist count will drop unless approved removal automation actually ran and was verified through the YouTube API.

## Runner pattern

Use two loops:

1. A worker that does real work, holds a lock, and writes checkpoints.
2. A watchdog that starts the worker if absent and reports only meaningful deltas.

Do not make a short cron timeout own a long research job.

## Required metrics in every report

```text
live_playlist_count: <from YouTube API>
state_rows: <local rows>
pending_transcripts: <count>
transcripts_done: <count>
pending_analysis: <count>
analyzed: <count>
pending_save: <count>
kb_saved: <count>
queued_for_removal: <count>
removed_this_run: <count>
playlist_count_delta: <before-after>
next_bottleneck: <catalog|transcript|analysis|save|removal>
```

## Safety boundaries

Safe to automate:

- read playlist metadata;
- fetch transcripts;
- run local or cloud analysis;
- write notes;
- append a processed ledger;
- append a removal queue.

Requires explicit approval:

- deleting/removing videos from a playlist;
- using OAuth write scopes;
- posting comments;
- sending reports to public channels;
- overwriting existing research notes.

## Acceptance test

Before calling the pipeline fixed, run a 1-3 video test and verify:

1. transcript fetched or error recorded;
2. analysis generated;
3. note written with the required sections;
4. processed ledger updated;
5. removal queue updated only if the note was saved;
6. live playlist count unchanged when queue-only mode is used;
7. rerunning the same batch does not duplicate notes or reprocess completed IDs.

## Common failure modes

| Failure | Symptom | Fix |
|---|---|---|
| Transcript-only trickle | transcripts rise, analysis and saves stay at zero | continue downstream for completed transcript rows |
| No checkpointing | timeout loses all progress | save state after every video or small batch |
| Overlarge analysis batch | worker dies in LLM phase | use a separate analysis limit |
| False deletion claim | removal queue grows but playlist count stays the same | report “queued only” until deletion is approved and verified |
| State overwrite | catalog step erases transcript progress | preserve state and append new playlist rows |
