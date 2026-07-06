#!/usr/bin/env python3
"""Tests for ARES Usage Tracker."""

import json
import os
import sys
import time
import tempfile
import unittest

# Point to the tracker module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools", "usage-tracker"))
import tracker


class TestUsageTracker(unittest.TestCase):

    def setUp(self):
        """Use temp files for each test."""
        self.tmpdir = tempfile.mkdtemp()
        self.orig_data_dir = tracker.DATA_DIR
        tracker.DATA_DIR = self.tmpdir
        tracker.DATA_FILE = os.path.join(self.tmpdir, "usage_tracker.json")
        tracker.STATE_FILE = os.path.join(self.tmpdir, "provider_state.json")

    def tearDown(self):
        tracker.DATA_DIR = self.orig_data_dir
        tracker.DATA_FILE = os.path.join(self.orig_data_dir, "usage_tracker.json")
        tracker.STATE_FILE = os.path.join(self.orig_data_dir, "provider_state.json")
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_record_and_usage(self):
        """Recording a request should update usage stats."""
        tracker.record("ollama-cloud", "deepseek-v4-flash")
        usage = tracker.get_usage("ollama-cloud", window="weekly")
        self.assertEqual(usage["request_count"], 1)
        self.assertEqual(usage["total_weight"], 2)  # deepseek-v4-flash = weight 2
        self.assertGreater(usage["remaining"], 0)

    def test_multiple_requests(self):
        """Multiple requests accumulate weight correctly."""
        for _ in range(10):
            tracker.record("ollama-cloud", "deepseek-v4-flash")
        usage = tracker.get_usage("ollama-cloud", window="weekly")
        self.assertEqual(usage["request_count"], 10)
        self.assertEqual(usage["total_weight"], 20)

    def test_burn_rate_calculation(self):
        """Burn rate should be > 0 after recording requests."""
        for _ in range(50):
            tracker.record("ollama-cloud", "deepseek-v4-flash")
        burn = tracker.get_burn_rate("ollama-cloud")
        self.assertGreater(burn["rate_per_hour"], 0)
        self.assertIn("will_exhaust_before_reset", burn)

    def _bulk_record(self, provider: str, model: str, count: int):
        """Fast bulk record — injects directly into the data store."""
        data = tracker._load()
        now = time.time()
        weight = tracker.get_weight(model)
        for i in range(count):
            data["requests"].append({
                "provider": provider,
                "model": model,
                "weight": weight,
                "timestamp": now - (i * 10),
                "response_length": 0,
            })
        tracker._save(data)

    def test_depletion_threshold(self):
        """Provider should be marked depleted at 80%+ projected usage."""
        budget = tracker.DEFAULT_BUDGETS["ollama-cloud"]  # 5000
        # Fill to 80% = 4000 weight units, each request = weight 2
        self._bulk_record("ollama-cloud", "deepseek-v4-flash", 2000)
        result = tracker.evaluate_routing()
        self.assertTrue(result["providers"]["ollama-cloud"]["depleted"])
        self.assertIn("ollama-cloud", result["depleted"])

    def test_provider_chain_priority(self):
        """Active provider should be first non-depleted in priority order."""
        self._bulk_record("ollama-cloud", "deepseek-v4-flash", 2000)
        result = tracker.evaluate_routing()
        # xai-oauth should be active (first in priority, not depleted)
        self.assertEqual(result["active_provider"], "xai-oauth")

    def test_all_providers_depleted(self):
        """When all providers are depleted, active should be None."""
        for p in ["xai-oauth", "openai-codex", "ollama-cloud"]:
            budget = tracker.DEFAULT_BUDGETS.get(p, 5000)
            requests_needed = budget // 2 + 1
            self._bulk_record(p, "deepseek-v4-flash", requests_needed)
        result = tracker.evaluate_routing()
        # All should be depleted
        for p in ["xai-oauth", "openai-codex", "ollama-cloud"]:
            self.assertTrue(result["providers"][p]["depleted"], f"{p} should be depleted")

    def test_reset_provider(self):
        """Reset should clear all requests for a provider."""
        for _ in range(10):
            tracker.record("ollama-cloud", "deepseek-v4-flash")
        tracker.reset_provider("ollama-cloud")
        usage = tracker.get_usage("ollama-cloud", window="weekly")
        self.assertEqual(usage["request_count"], 0)
        self.assertEqual(usage["total_weight"], 0)

    def test_set_budget(self):
        """Setting a budget should persist and affect calculations."""
        tracker.set_budget("ollama-cloud", 100)
        usage = tracker.get_usage("ollama-cloud", window="weekly")
        self.assertEqual(usage["budget"], 100)

    def test_model_weight_lookup(self):
        """Model weight lookup should return correct values."""
        self.assertEqual(tracker.get_weight("gpt-oss:20b"), 1)
        self.assertEqual(tracker.get_weight("deepseek-v4-flash"), 2)
        self.assertEqual(tracker.get_weight("glm-5.1"), 4)
        self.assertEqual(tracker.get_weight("unknown-model"), tracker.DEFAULT_WEIGHT)

    def test_session_window(self):
        """Session window (5h) should be shorter than weekly window."""
        session = tracker.get_usage("ollama-cloud", window="session")
        weekly = tracker.get_usage("ollama-cloud", window="weekly")
        self.assertLess(session["window_seconds"], weekly["window_seconds"])

    def test_evaluate_output_format(self):
        """evaluate_routing should return expected keys."""
        result = tracker.evaluate_routing()
        self.assertIn("active_provider", result)
        self.assertIn("depleted", result)
        self.assertIn("providers", result)
        for p in ["xai-oauth", "openai-codex", "ollama-cloud"]:
            self.assertIn(p, result["providers"])
            info = result["providers"][p]
            self.assertIn("depleted", info)
            self.assertIn("pct_used", info)
            self.assertIn("remaining", info)

    def test_summary_output(self):
        """summary() should return a non-empty string."""
        s = tracker.summary()
        self.assertIsInstance(s, str)
        self.assertGreater(len(s), 0)
        self.assertIn("Active provider", s)


if __name__ == "__main__":
    unittest.main()
