"""ARES Deep Researcher — IterResearch-style deep research engine.

Ported from Odysseus src/deep_research.py (929 lines).
Adapted for ARES:
  - Uses ARES backend router for LLM calls (not direct OpenAI)
  - Uses ARES web_search/web_extract for search (not SearXNG)
  - Uses ARES session system for progress callbacks
  - Removed Odysseus-specific settings/config imports

The iterative loop: Plan → Generate queries → Search → Extract → Synthesize →
Check completeness → Repeat or finalize.

License: AGPL-3.0
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from datetime import datetime
from typing import Callable, Dict, List, Optional, Set

from api.research.utils import strip_thinking, is_low_quality
from api.research.prompts import EXTRACTOR_SYSTEM

logger = logging.getLogger(__name__)


def current_date_context() -> str:
    """Preamble that grounds query-generation/planning LLMs in the real date."""
    now = datetime.now().astimezone()
    return (
        f"Today's date is {now.strftime('%B %d, %Y')} ({now.strftime('%Y-%m-%d')}). "
        f"When a search query needs a year or refers to 'latest'/'current'/"
        f"'this year', use {now.strftime('%Y')} or relative wording — never a "
        f"year inferred from training data.\n\n"
    )


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------
RESEARCH_PLAN_PROMPT = """\
You are a research strategist. Before searching, analyze this question and create a research plan.

**Question:** {question}

Break this question down:
1. What are the key sub-topics that need to be covered for a comprehensive answer?
2. What specific data points, facts, or perspectives should we look for?
3. What would a complete, high-quality answer include?

Return a JSON object with:
- "sub_questions": Array of 3-6 specific sub-questions to investigate
- "key_topics": Array of key topics/angles to cover
- "success_criteria": One sentence describing what a complete answer looks like

Example:
{{
  "sub_questions": ["What is the cost of living in X?", "How is the healthcare system?"],
  "key_topics": ["economy", "healthcare", "safety", "culture"],
  "success_criteria": "A balanced comparison covering cost, quality of life, and practical considerations."
}}
"""

QUERY_GEN_PROMPT = """\
You are a research assistant planning web searches.

**Original question:** {question}

**Research plan:**
{research_plan}

**What we know so far:**
{report}

**Round:** {round_num}

Generate {num_queries} focused search queries that will help answer the question.
{round_instruction}

Return ONLY a JSON array of query strings, nothing else.
Example: ["query one", "query two", "query three"]
"""

SYNTHESIZE_PROMPT = """\
You are updating an evolving research report.

**Original question:** {question}

**Current report:**
{report}

**New findings from this round:**
{new_findings}

Integrate the new findings into the existing report. Produce an updated, well-organized \
report that answers the original question as completely as possible given all evidence so far. \
Remove redundancy, resolve contradictions, and maintain logical flow. \
Keep source URLs as inline citations where relevant.

Write only the updated report — no preamble or meta-commentary.
"""

STOP_PROMPT = """\
You are deciding whether a research report is comprehensive enough.

**Original question:** {question}

**Current report:**
{report}

**Rounds completed:** {round_num} of {max_rounds}

Based on the report so far, do we have enough information to answer the question \
comprehensively?  Consider:
- Are the key aspects of the question addressed?
- Are there obvious gaps or unanswered sub-questions?
- Is the evidence sufficient and from multiple sources?

If rounds completed is well below the target, prefer continuing unless the \
report is already exhaustive.

Reply with ONLY "YES" or "NO" followed by a brief one-sentence reason.
Example: "YES — The report covers all major aspects with evidence from multiple sources."
Example: "NO — We still lack information about the economic impact."
"""

FINAL_REPORT_PROMPT = """\
Write a **long, detailed, comprehensive** research report answering this question:

**Question:** {question}

**All collected evidence and analysis:**
{report}

Requirements:
- Write at MINIMUM 1500 words — this should be a thorough, magazine-quality article
- Use clear ## headings and ### subheadings to organize into logical sections
- Each section should have multiple detailed paragraphs, not just bullet points
- Synthesize and analyze the information — explain WHY things matter, draw comparisons, provide context
- Include specific data points, numbers, and statistics from the evidence
- Include source URLs as inline citations [like this](url)
- Note where sources agree and where they disagree
- Add a brief executive summary at the top
- End with a clear conclusion that directly answers the question
- Write in an engaging, informative style — not dry or robotic
"""

CATEGORY_PROMPTS = {
    "product": """IMPORTANT FORMAT OVERRIDE — this is a PRODUCT research report:
- Structure as a RANKED LIST of products/options (best first)
- For EACH product include: name as ### heading, approximate price, 2-3 sentence summary, **Pros:** bullet list, **Cons:** bullet list, **Where to buy:** URLs as links
- Start with a quick-compare markdown table of top picks (columns: Name, Price, Best For, Rating)
- End with a ## Verdict section picking Best Overall and Best Value
- Still include source citations inline""",

    "comparison": """IMPORTANT FORMAT OVERRIDE — this is a COMPARISON report:
- Create a ## Comparison Table as a markdown table comparing ALL options across key criteria (rows = criteria, columns = options)
- Use checkmarks, ratings, or short values in cells
- Write a ## section per option with its strengths, weaknesses, and ideal use case
- End with ## Best For verdicts (e.g., "**Best for small teams:** Option A because...")
- Include a ## Shared Considerations section for things that apply to all options""",

    "howto": """IMPORTANT FORMAT OVERRIDE — this is a HOW-TO guide:
- Start with ## Quick Guide — a super concise numbered list (one line per step, no details, just the action). Example: 1. Install X  2. Run Y  3. Configure Z
- Then ## Prerequisites listing what's needed before starting
- Then the detailed steps: ## Step 1: ..., ## Step 2: ...
- Each step should have a clear heading and detailed instructions
- Use blockquotes (> ) for tips and warnings: > **Tip:** ... or > **Warning:** ...
- End with ## Common Mistakes section
- Add estimated time and difficulty level near the top""",

    "factcheck": """IMPORTANT FORMAT OVERRIDE — this is a FACT-CHECK report:
- Start with ## The Claim restating what's being checked
- Create ## Evidence For and ## Evidence Against sections
- Each piece of evidence should be a ### with source name, what it found, and how strong the evidence is
- Include a ## Verdict section with one of: **Supported**, **Mixed Evidence**, or **Unsupported**
- End with ## Nuance & Caveats for important context and limitations
- Be balanced and cite sources for every claim""",
}


class DeepResearcher:
    """
    Iterative research engine following the IterResearch pattern.

    Each round: LLM generates queries → web search → LLM extracts from
    top pages → LLM synthesizes into evolving report → LLM decides continue/stop.
    """

    def __init__(
        self,
        llm_call_fn: Optional[Callable] = None,
        search_fn: Optional[Callable] = None,
        extract_fn: Optional[Callable] = None,
        max_rounds: int = 8,
        max_time: int = 300,
        max_urls_per_round: int = 3,
        max_content_chars: int = 15000,
        max_report_tokens: int = 8192,
        extraction_timeout: int = 90,
        planning_timeout: int = 90,
        query_timeout: int = 120,
        min_rounds: int = 2,
        max_empty_rounds: int = 2,
        progress_callback: Optional[Callable] = None,
        category: Optional[str] = None,
    ):
        # Callable interfaces — ARES injects these
        self.llm_call_fn = llm_call_fn
        self.search_fn = search_fn
        self.extract_fn = extract_fn
        self.category = category
        self.max_rounds = max_rounds
        self.max_time = max_time
        self.max_urls_per_round = max_urls_per_round
        self.max_content_chars = max_content_chars
        self.max_report_tokens = max_report_tokens
        self.extraction_timeout = max(15, min(3600, extraction_timeout))
        self.planning_timeout = max(15, min(3600, planning_timeout))
        self.query_timeout = max(15, min(3600, query_timeout))
        self.min_rounds = min_rounds
        self.max_empty_rounds = max_empty_rounds
        self._progress = progress_callback
        self._cancelled = False
        self._start_time: float = 0

        # State
        self.queries_used: Set[str] = set()
        self.urls_fetched: Set[str] = set()
        self.analyzed_urls: List[Dict[str, str]] = []
        self.round_count: int = 0
        self.findings: List[Dict] = []
        self.evolving_report: str = ""
        self.research_plan: str = ""

    def cancel(self):
        """Request cooperative cancellation of the research loop."""
        self._cancelled = True

    def _emit(self, phase: str, **kwargs):
        """Emit progress event to callback."""
        if self._progress:
            try:
                self._progress({"phase": phase, **kwargs})
            except Exception:
                pass

    # ------------------------------------------------------------------
    # LLM calls — delegates to injected callable
    # ------------------------------------------------------------------
    async def _llm_call(self, prompt: str, system: str = "", timeout: int = 120) -> Optional[str]:
        """Call the LLM through the injected callable."""
        if not self.llm_call_fn:
            logger.error("No LLM callable configured for DeepResearcher")
            return None
        try:
            result = await self.llm_call_fn(prompt=prompt, system=system, timeout=timeout)
            return strip_thinking(result)
        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            return None

    # ------------------------------------------------------------------
    # Search — delegates to injected callable
    # ------------------------------------------------------------------
    async def _search(self, query: str) -> List[Dict]:
        """Search the web through the injected callable. Returns [{title, url, snippet}]."""
        if not self.search_fn:
            logger.error("No search callable configured for DeepResearcher")
            return []
        try:
            results = await self.search_fn(query)
            return results if isinstance(results, list) else []
        except Exception as e:
            logger.error(f"Search failed for '{query}': {e}")
            return []

    # ------------------------------------------------------------------
    # Extraction — delegates to injected callable or falls back to raw content
    # ------------------------------------------------------------------
    async def _extract(self, url: str, goal: str) -> Optional[Dict]:
        """Extract relevant content from a URL for a given research goal."""
        if self.extract_fn:
            try:
                return await self.extract_fn(url=url, goal=goal)
            except Exception as e:
                logger.error(f"Extraction failed for {url}: {e}")
                return None

        # Fallback: use web_extract-like approach (handled by the caller)
        return None

    # ------------------------------------------------------------------
    # Planning
    # ------------------------------------------------------------------
    async def _create_plan(self, question: str) -> str:
        """Generate a research plan for the question."""
        prompt = RESEARCH_PLAN_PROMPT.format(question=question)
        result = await self._llm_call(prompt, timeout=self.planning_timeout)
        if result:
            # Try to extract JSON from the response
            try:
                # Find JSON in response
                match = re.search(r'\{[\s\S]*\}', result)
                if match:
                    plan = json.loads(match.group())
                    return json.dumps(plan, indent=2)
            except json.JSONDecodeError:
                pass
            return result
        return "{}"

    async def _classify_category(self, question: str) -> Optional[str]:
        """Auto-detect the research category."""
        prompt = f"""Classify this research question into one of these categories:
- product: asking for product recommendations or reviews
- comparison: asking to compare multiple options
- howto: asking how to do something
- factcheck: asking to verify a claim or fact
- general: anything else

Question: {question}

Reply with ONLY the category name, nothing else."""
        result = await self._llm_call(prompt, timeout=30)
        if result:
            cat = result.strip().lower()
            if cat in CATEGORY_PROMPTS:
                return cat
        return None

    # ------------------------------------------------------------------
    # Query generation
    # ------------------------------------------------------------------
    async def _generate_queries(self, question: str, report: str, round_num: int) -> List[str]:
        """Generate search queries for the current round."""
        round_instruction = ""
        if round_num == 1:
            round_instruction = "Focus on breadth — cover different aspects of the question."
        elif round_num == 2:
            round_instruction = "Focus on depth — dig deeper into the most promising areas from round 1."
        else:
            round_instruction = "Focus on filling gaps in the current report."

        prompt = QUERY_GEN_PROMPT.format(
            question=question,
            research_plan=self.research_plan,
            report=report or "No information gathered yet.",
            round_num=round_num,
            num_queries=min(3, max(2, 4 - round_num // 2)),
            round_instruction=round_instruction,
        )
        result = await self._llm_call(prompt, timeout=self.query_timeout)
        if not result:
            return []

        # Parse JSON array of queries
        try:
            match = re.search(r'\[[\s\S]*\]', result)
            if match:
                queries = json.loads(match.group())
                # Filter out already-used queries
                new_queries = [q for q in queries if isinstance(q, str) and q not in self.queries_used]
                return new_queries[:3]
        except json.JSONDecodeError:
            # Try line-by-line parsing
            lines = [l.strip().strip('"').strip("'") for l in result.split('\n') if l.strip()]
            return [q for q in lines[:3] if q not in self.queries_used]

        return []

    # ------------------------------------------------------------------
    # Extraction from search results
    # ------------------------------------------------------------------
    async def _extract_from_results(
        self, question: str, results: List[Dict]
    ) -> List[Dict]:
        """Extract relevant content from search result URLs."""
        findings = []
        urls_to_process = []
        for r in results[:self.max_urls_per_round]:
            url = r.get("url", "")
            if url and url not in self.urls_fetched:
                urls_to_process.append(r)

        for r in urls_to_process:
            url = r.get("url", "")
            title = r.get("title", "")
            snippet = r.get("snippet", "") or r.get("description", "")
            self.urls_fetched.add(url)
            self.analyzed_urls.append({"url": url, "title": title})

            # Try goal-based extraction
            extracted = await self._extract(url, question)
            if extracted and not is_low_quality(extracted.get("summary", "")):
                findings.append({
                    "url": url,
                    "title": title,
                    "summary": extracted.get("summary", ""),
                    "evidence": extracted.get("evidence", snippet),
                    "round": self.round_count,
                })
            elif snippet:
                # Fall back to search snippet
                findings.append({
                    "url": url,
                    "title": title,
                    "summary": snippet,
                    "evidence": snippet,
                    "round": self.round_count,
                })

        return findings

    # ------------------------------------------------------------------
    # Synthesis
    # ------------------------------------------------------------------
    async def _synthesize(self, question: str, report: str, new_findings: List[Dict]) -> str:
        """Integrate new findings into the evolving report."""
        findings_text = "\n\n".join(
            f"**Source: [{f['title']}]({f['url']})**\n{f['evidence']}"
            for f in new_findings if f.get("evidence")
        )
        prompt = SYNTHESIZE_PROMPT.format(
            question=question,
            report=report or "No report yet — start from scratch with these findings.",
            new_findings=findings_text,
        )
        result = await self._llm_call(prompt, timeout=self.extraction_timeout)
        return result or report or ""

    # ------------------------------------------------------------------
    # Stopping condition
    # ------------------------------------------------------------------
    async def _should_stop(self, question: str, report: str) -> bool:
        """Ask the LLM whether the report is comprehensive enough."""
        if self.round_count < self.min_rounds:
            return False
        prompt = STOP_PROMPT.format(
            question=question,
            report=report[:4000],
            round_num=self.round_count,
            max_rounds=self.max_rounds,
        )
        result = await self._llm_call(prompt, timeout=30)
        if result:
            return result.strip().upper().startswith("YES")
        return False

    # ------------------------------------------------------------------
    # Stats
    # ------------------------------------------------------------------
    def get_stats(self) -> Dict:
        return {
            "Rounds": self.round_count,
            "Queries": len(self.queries_used),
            "URLs": len(self.urls_fetched),
            "Findings": len(self.findings),
        }

    # ------------------------------------------------------------------
    # Main research loop
    # ------------------------------------------------------------------
    async def research(
        self,
        question: str,
        prior_report: str = "",
        prior_findings: Optional[List[Dict]] = None,
        prior_urls: Optional[Set[str]] = None,
    ) -> str:
        """Run iterative research and return a final report."""
        self._start_time = time.time()
        findings: List[Dict] = list(prior_findings) if prior_findings else []
        report = prior_report or ""
        consecutive_empty = 0

        # PLAN
        self._emit(phase="planning")
        self.research_plan = await self._create_plan(question)
        logger.info(f"Research plan: {self.research_plan[:200]}")

        if not self.category and not prior_report:
            self.category = await self._classify_category(question)
            if self.category:
                logger.info(f"Auto-detected category: {self.category}")

        if prior_urls:
            self.urls_fetched.update(prior_urls)
        self.findings = findings

        # ITERATE
        for round_num in range(1, self.max_rounds + 1):
            if self._cancelled:
                logger.info("Research cancelled")
                break

            elapsed = time.time() - self._start_time
            if elapsed > self.max_time:
                logger.info(f"Research timed out after {elapsed:.0f}s")
                break

            self.round_count = round_num
            self._emit(phase="search", round=round_num)

            # Generate queries
            queries = await self._generate_queries(question, report, round_num)
            if not queries:
                consecutive_empty += 1
                if consecutive_empty >= self.max_empty_rounds:
                    logger.info(f"Stopping: {consecutive_empty} empty rounds")
                    break
                continue

            consecutive_empty = 0
            self.queries_used.update(queries)

            # Search
            all_results = []
            for query in queries:
                results = await self._search(query)
                all_results.extend(results)

            # Extract
            new_findings = await self._extract_from_results(question, all_results)
            findings.extend(new_findings)
            self.findings = findings

            # Synthesize
            self._emit(phase="synthesis", round=round_num)
            report = await self._synthesize(question, report, new_findings)

            # Check completeness
            if round_num >= self.min_rounds:
                should_stop = await self._should_stop(question, report)
                if should_stop:
                    logger.info(f"Research complete after {round_num} rounds")
                    break

        # Final report
        self._emit(phase="finalizing")
        final = await self._finalize(question, report)
        self.evolving_report = final
        return final

    async def _finalize(self, question: str, report: str) -> str:
        """Generate the final polished report."""
        category_suffix = CATEGORY_PROMPTS.get(self.category or "", "")
        prompt = FINAL_REPORT_PROMPT.format(question=question, report=report)
        if category_suffix:
            prompt += f"\n\n{category_suffix}"
        result = await self._llm_call(prompt, timeout=self.extraction_timeout * 2)
        return result or report