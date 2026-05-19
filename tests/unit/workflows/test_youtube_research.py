"""Unit tests for the YouTube research pipeline."""

from __future__ import annotations

import pytest
from datetime import datetime

from ares.workflows.research_models import (
    CompetitorChannel,
    ResearchBrief,
    ResearchItem,
    ResearchResult,
    TopicScore,
    VideoFormat,
)


class TestTopicScore:
    def test_passed_threshold(self):
        s = TopicScore(relevance=5, timeliness=3, differentiation=4, feasibility=3, hook_strength=4)
        assert s.total == 19
        assert s.passed is True

    def test_failed_threshold(self):
        s = TopicScore(relevance=2, timeliness=2, differentiation=2, feasibility=2, hook_strength=2)
        assert s.total == 10
        assert s.passed is False

    def test_boundary_pass(self):
        s = TopicScore(relevance=3, timeliness=3, differentiation=3, feasibility=3, hook_strength=3)
        assert s.total == 15
        assert s.passed is True


class TestResearchBrief:
    def test_summary_text_includes_hook(self):
        b = ResearchBrief(
            topic="JP01 Arm Build",
            hook="Complete walkthrough from CAD to test",
            score=TopicScore(relevance=5, timeliness=3, differentiation=4, feasibility=3, hook_strength=4),
            script_outline=["CAD", "Print", "Assemble", "Test"],
            differentiator="Failures shown",
        )
        summary = b.summary_text
        assert "JP01 Arm Build" in summary
        assert "Complete walkthrough" in summary
        assert "PASS" in summary
        assert "Failures shown" in summary

    def test_competitor_gap_field(self):
        b = ResearchBrief(
            topic="Test",
            score=TopicScore(relevance=5, timeliness=3, differentiation=4, feasibility=3, hook_strength=4),
            competitor_gap="No one does X",
        )
        assert b.competitor_gap == "No one does X"


class TestResearchResult:
    def test_passed_briefs_filter(self):
        r = ResearchResult(
            query="robotics",
            briefs=[
                ResearchBrief(
                    topic="Good",
                    score=TopicScore(relevance=5, timeliness=3, differentiation=4, feasibility=3, hook_strength=4),
                    script_outline=[],
                    differentiator="",
                ),
                ResearchBrief(
                    topic="Bad",
                    score=TopicScore(relevance=2, timeliness=2, differentiation=2, feasibility=2, hook_strength=2),
                    script_outline=[],
                    differentiator="",
                ),
            ],
        )
        passed = r.passed_briefs()
        assert len(passed) == 1
        assert passed[0].topic == "Good"

    def test_default_competitors(self):
        r = ResearchResult(query="test", competitors=[])
        assert r.competitors == []


class TestCompetitorChannel:
    def test_model_creation(self):
        c = CompetitorChannel(
            name="Cogley",
            subscribers="244K",
            view_range="30K–464K",
            strength="Documentation",
            weakness="Noisy servos",
        )
        assert c.name == "Cogley"
        assert c.weakness == "Noisy servos"

    def test_last_scraped_optional(self):
        c = CompetitorChannel(name="Test", subscribers="0")
        assert c.last_scraped is None
