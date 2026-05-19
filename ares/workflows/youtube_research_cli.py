"""YouTube research CLI — `ares youtube research`.

Runs Pydantic v2-validated content research and outputs scored proposals
ready for the video production pipeline.  No LLM call is required; you
seed the pipeline with a topic and competitive context, and ARES scores
and formats the output.

Usage:
    ares youtube research "robot arm build" --briefs 3
    ares youtube research --load-json topic_proposals.json --output-dir ~/Downloads
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

import click

from ares.workflows.research_models import (
    CompetitorChannel,
    ContentPlatform,
    ResearchBrief,
    ResearchItem,
    ResearchResult,
    TopicScore,
    VideoFormat,
)


# ──  built-in competitive landscape  ────────────────────────────────────────

DEFAULT_COMPETITORS: list[CompetitorChannel] = [
    CompetitorChannel(
        name="Kiara's Workshop",
        subscribers="338K",
        view_range="150K–2.5M",
        strength="Cosplay × robotics, character builds",
        weakness="Different angle, overlapping audience",
    ),
    CompetitorChannel(
        name="Will Cogley",
        subscribers="244K",
        view_range="30K–464K",
        strength="Open-source animatronics, documented builds",
        weakness="Loud servos, no personality",
    ),
    CompetitorChannel(
        name="Jeremy Fielding",
        subscribers="1.11M",
        view_range="100K–5M",
        strength="Educational engineering builds",
        weakness="Broader, less character-focused",
    ),
    CompetitorChannel(
        name="Disney Research Hub",
        subscribers="136K",
        view_range="2K–121K",
        strength="RL-based character robotics (Olaf)",
        weakness="Academic-only, not DIY/maker",
    ),
    CompetitorChannel(
        name="Skyentific",
        subscribers="256K",
        view_range="10K–64K",
        strength="Robotic arms, NVIDIA ecosystem",
        weakness="Academic/industrial, not consumer",
    ),
]

# ──  proposal helpers  ──────────────────────────────────────────────────

def _build_brief(topic: str, idx: int) -> ResearchBrief:
    """Generate one scored brief from a topic seed."""
    prompts = [
        (
            f'"{topic}" — Full Build Breakdown',
            f"Complete walkthrough of the {topic} project from CAD to test",
            VideoFormat.solo_build,
            ["CAD modelling", "3D printing", "assembly", "testing fails", "final demo"],
            ["CAD screen recording", "timelapse prints", "shop floor assembly", "demo footage"],
        ),
        (
            f'{topic}: What Went Wrong',
            "Honest failure log and lessons learned from the build",
            VideoFormat.vlog,
            ["The plan", "First failure", "Second failure", "What I learned", "Next iteration"],
            ["failed prototypes", "lab / shop footage", "whiteboard explanations"],
        ),
        (
            f'Building {topic} with Local LLMs',
            f"Using ARES to design and debug the {topic} without cloud APIs",
            VideoFormat.deep_dive,
            ["Why local AI", "Setting up ARES", "Design iterations", "Live debugging", "Results"],
            [ "screen recordings", "terminal output", "JP01 hardware shots", "comparison charts"],
        ),
    ]

    title, hook, fmt, outline, broll = prompts[idx % len(prompts)]

    # Dynamic scoring — higher feasibility for simpler formats
    if fmt == VideoFormat.short:
        feas = 5
    elif fmt == VideoFormat.vlog:
        feas = 4
    else:
        feas = 3

    score = TopicScore(
        relevance=5,
        timeliness=3,
        differentiation=4,
        feasibility=feas,
        hook_strength=4,
    )

    return ResearchBrief(
        id=f"{datetime.now().strftime('%Y%m%d')}-{uuid.uuid4().hex[:6]}",
        topic=title,
        hook=hook,
        runtime_min=10 if fmt != VideoFormat.short else 1,
        thumbnail_text=title.split("—")[0].strip()[:5] if "—" in title else topic[:5],
        thumbnail_style="Bold mechanical / high contrast",
        score=score,
        competitor_gap="No one pairs open-source CAD with live debugging in robotics",
        script_outline=outline,
        b_roll_needs=broll,
        differentiator="Real failures shown, not just polished successes",
        references=[],
    )


# ──  CLI  ──────────────────────────────────────────────────────────────────

@click.group(name="youtube")
def yt_cli():
    """ARES YouTube content research and video production pipeline."""
    pass


@yt_cli.command(name="research")
@click.argument("topic", required=False)
@click.option("--briefs", "-b", default=3, type=int, help="Number of proposals to generate")
@click.option("--output-dir", "-o", type=click.Path(), help="Directory to write JSON output")
@click.option("--json", "as_json", is_flag=True, help="Print JSON instead of pretty text")
@click.option("--load-json", type=click.Path(exists=True), help="Load topic list from JSON [{\"topic\":\"...\"}]")
def research_cmd(topic: str | None, briefs: int, output_dir: str | None, as_json: bool, load_json: str | None):
    """Research a topic and output scored video proposals.

    Examples:
        ares youtube research "JP01 robot arm"
        ares youtube research --briefs 5 "deep dive on PMSM motors"
        ares youtube research --load-json ideas.json --output-dir ~/Downloads/research
    """
    topics: list[str] = []

    if load_json:
        data = json.loads(Path(load_json).read_text())
        if isinstance(data, list):
            topics = [d["topic"] if isinstance(d, dict) else str(d) for d in data]
        else:
            topics = [data.get("topic", str(data))]
    elif topic:
        topics = [topic]
    else:
        click.echo("❌  Provide a TOPIC or --load-json", err=True)
        raise click.Abort()

    all_results: list[ResearchResult] = []

    for t in topics:
        result = ResearchResult(query=t, competitors=DEFAULT_COMPETITORS.copy())
        for i in range(briefs):
            result.briefs.append(_build_brief(t, i))
        all_results.append(result)

        if not as_json and len(topics) == 1:
            click.echo(f"\n{'='*60}")
            click.echo(f"🔍  Research: {t}")
            click.echo(f"{'='*60}")
            passed = result.passed_briefs()
            click.echo(f"\n{len(passed)}/{len(result.briefs)} proposals scored ≥15/25\n")
            for b in result.briefs:
                status = "✅ PASS" if b.score.passed else "❌ FAIL"
                click.echo(f"\n{'─'*60}")
                click.echo(f"{status}  ({b.score.total}/25)")
                click.echo(b.summary_text)
                click.echo(f"\n🎥  Format: {b.runtime_min} min  |  B-roll: {len(b.b_roll_needs)} items")

    if as_json:
        combined = {
            "results": [r.model_dump(mode="json") for r in all_results],
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
        click.echo(json.dumps(combined, indent=2, ensure_ascii=False))

    if output_dir:
        out = Path(output_dir)
        out.mkdir(parents=True, exist_ok=True)
        for r in all_results:
            fname = out / f"research_{r.query.replace(' ', '_')[:40]}_{r.created_at.strftime('%Y%m%d')}.json"
            fname.write_text(r.model_dump_json(indent=2), encoding="utf-8")
            click.echo(f"\n💾  Saved: {fname}")


@yt_cli.command(name="competitors")
@click.option("--json", "as_json", is_flag=True, help="Output as JSON")
def competitors_cmd(as_json: bool):
    """Show the curated competitive landscape."""
    if as_json:
        data = [c.model_dump(mode="json") for c in DEFAULT_COMPETITORS]
        click.echo(json.dumps(data, indent=2, ensure_ascii=False))
    else:
        click.echo("\n🏆  Competitive Landscape\n")
        for c in DEFAULT_COMPETITORS:
            click.echo(f"  📺  {c.name}  ({c.subscribers})")
            click.echo(f"      Views: {c.view_range}")
            click.echo(f"      💪  {c.strength}")
            click.echo(f"      🚨  {c.weakness}\n")


# ──  wiring  ───────────────────────────────────────────────────────────────

def register(cli: click.Group) -> None:
    """Attach `ares youtube` subcommands to the main CLI."""
    cli.add_command(yt_cli)


if __name__ == "__main__":
    yt_cli()
