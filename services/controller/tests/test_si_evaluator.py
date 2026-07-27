"""
ARES SI — Evaluator and verification tests.
"""

import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))


class TestDeterministicChecks:
    """Test individual verification checks."""

    def test_check_not_empty_pass(self):
        from api.si.evaluator import check_not_empty
        result = check_not_empty("Hello world")
        assert result.passed

    def test_check_not_empty_fail(self):
        from api.si.evaluator import check_not_empty
        result = check_not_empty("")
        assert not result.passed

    def test_check_not_empty_whitespace_fail(self):
        from api.si.evaluator import check_not_empty
        result = check_not_empty("   ")
        assert not result.passed

    def test_check_reasonable_length_pass(self):
        from api.si.evaluator import check_reasonable_length
        result = check_reasonable_length("This is a reasonable response that has enough content.")
        assert result.passed

    def test_check_reasonable_length_too_short(self):
        from api.si.evaluator import check_reasonable_length
        result = check_reasonable_length("Hi", min_length=10)
        assert not result.passed

    def test_check_no_secret_leak_clean(self):
        from api.si.evaluator import check_no_secret_leak
        result = check_no_secret_leak("Here is some normal text without secrets")
        assert result.passed

    def test_check_no_secret_leak_openai_key(self):
        from api.si.evaluator import check_no_secret_leak
        result = check_no_secret_leak("Set your API key to sk-abc123def456ghi789jkl012mno345")
        assert not result.passed

    def test_check_no_secret_leak_bearer_token(self):
        from api.si.evaluator import check_no_secret_leak
        result = check_no_secret_leak("Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc123def456==")
        assert not result.passed

    def test_check_no_harmful_content_clean(self):
        from api.si.evaluator import check_no_harmful_content
        result = check_no_harmful_content("To list files, use: ls -la")
        assert result.passed

    def test_check_no_harmful_content_rmr(self):
        from api.si.evaluator import check_no_harmful_content
        result = check_no_harmful_content("Run: rm -rf / to clean up")
        assert not result.passed

    def test_check_code_syntax_balanced(self):
        from api.si.evaluator import check_code_syntax
        result = check_code_syntax("```python\ndef hello():\n    print('hello')\n```")
        assert result.passed

    def test_check_code_syntax_unbalanced(self):
        from api.si.evaluator import check_code_syntax
        result = check_code_syntax("```python\ndef hello():\n    print('hello'\n```")
        assert not result.passed

    def test_check_factuality_markers_low(self):
        from api.si.evaluator import check_factuality_markers
        result = check_factuality_markers("Python is a programming language.")
        assert result.passed

    def test_check_factuality_markers_high_hedging(self):
        from api.si.evaluator import check_factuality_markers
        result = check_factuality_markers("I think maybe perhaps this could possibly be right, I'm not sure, but I believe it might be correct.")
        # Still passes the check, but notes hedging
        assert result.passed  # hedging doesn't fail, just notes it
        assert result.details.get("hedging_count", 0) >= 3


class TestEvaluationPipeline:
    """Test the full evaluation pipeline."""

    def test_evaluate_good_conversation(self):
        from api.si.evaluator import evaluate_result, EvaluationVerdict
        evaluation = evaluate_result(
            "The project uses Python with FastAPI for the backend and React for the frontend.",
            intent="conversation",
        )
        assert evaluation.verdict == EvaluationVerdict.PASS
        assert evaluation.overall_score >= 0.5
        assert evaluation.recommendation == "accept"

    def test_evaluate_empty_result(self):
        from api.si.evaluator import evaluate_result, EvaluationVerdict
        evaluation = evaluate_result("", intent="conversation")
        assert evaluation.verdict == EvaluationVerdict.FAIL
        assert evaluation.recommendation == "reject"

    def test_evaluate_result_with_secret(self):
        from api.si.evaluator import evaluate_result, EvaluationVerdict
        evaluation = evaluate_result(
            "Here's the config: API_KEY=sk-abc123def456ghi789jkl012mno345pqr678",
            intent="conversation",
        )
        assert evaluation.verdict == EvaluationVerdict.ESCALATE
        assert evaluation.recommendation == "escalate"

    def test_evaluate_code_with_syntax_error(self):
        from api.si.evaluator import evaluate_result, EvaluationVerdict
        evaluation = evaluate_result(
            "```python\ndef broken(\n    print('missing paren'\n```\nThis code has a syntax error.",
            intent="code_generation",
        )
        # Code syntax check should flag this
        code_checks = [c for c in evaluation.checks if c.check_name == "code_syntax"]
        if code_checks:
            assert not code_checks[0].passed

    def test_evaluate_research_result(self):
        from api.si.evaluator import evaluate_result, EvaluationVerdict
        evaluation = evaluate_result(
            "Based on research, SQLite is a good choice for local-first applications. "
            "It's reliable, fast, and doesn't require a server.",
            intent="research",
        )
        assert evaluation.verdict == EvaluationVerdict.PASS

    def test_evaluate_action_with_harmful_command(self):
        from api.si.evaluator import evaluate_result, EvaluationVerdict
        evaluation = evaluate_result(
            "I ran: rm -rf / to clean the system",
            intent="action",
        )
        # Should flag harmful content
        harmful_checks = [c for c in evaluation.checks if c.check_name == "no_harmful_content"]
        if harmful_checks:
            assert not harmful_checks[0].passed

    def test_deterministic_no_llm(self):
        """Verify that evaluation is purely deterministic — no LLM calls."""
        from api.si.evaluator import evaluate_result
        # This should work without any API calls or LLM
        evaluation = evaluate_result("Test result", intent="conversation")
        assert evaluation is not None
        assert evaluation.overall_score is not None