"""MCP Tool: Hive Research — trigger and monitor research runs remotely."""

import json
import os
import subprocess
from datetime import datetime
from pathlib import Path


def register(mcp, config: dict):
    """Register hive research tools with the MCP server."""

    hr_config = config.get("tools", {}).get("hive_research", {})
    hive_path = Path(hr_config.get("path", "/srv/vault/04-repos/01-active/hive-research"))

    @mcp.tool()
    async def hive_mine(prompt_numbers: str = "") -> str:
        """Run the hive-research knowledge mining loop.

        Executes mine_loop.py to process prompts through multiple LLM providers.

        Args:
            prompt_numbers: Comma-separated prompt numbers to mine (e.g., "38,39").
                          Leave empty to process all unmined prompts.
        """
        if not hive_path.is_dir():
            return f"Error: Hive research path {hive_path} not found"

        cmd = [str(hive_path / "venv/bin/python"), str(hive_path / "tools/mine_loop.py")]
        if prompt_numbers:
            cmd.extend(["--prompts", prompt_numbers])

        try:
            result = subprocess.run(
                cmd,
                cwd=str(hive_path),
                capture_output=True,
                text=True,
                timeout=600,
                env={**os.environ, "PYTHONUNBUFFERED": "1"},
            )
            output = result.stdout + ("\n" + result.stderr if result.stderr else "")
            return output[-5000:]  # Last 5k chars
        except subprocess.TimeoutExpired:
            return "Mining timed out after 10 minutes. Check logs for progress."
        except Exception as e:
            return f"Error running mine_loop: {e}"

    @mcp.tool()
    async def hive_research(query: str, budget: str = "low") -> str:
        """Start a hive-research research run on a topic.

        Args:
            query: Research question or topic.
            budget: Budget level — "low" (~$0.10), "medium" (~$0.50), "high" (~$2.00).
        """
        if not hive_path.is_dir():
            return f"Error: Hive research path {hive_path} not found"

        cmd = [
            str(hive_path / "venv/bin/python"),
            str(hive_path / "core/research.py"),
            "--query", query,
            "--budget", budget,
            "--yes",
        ]

        try:
            result = subprocess.run(
                cmd,
                cwd=str(hive_path),
                capture_output=True,
                text=True,
                timeout=1200,
                env={**os.environ, "PYTHONUNBUFFERED": "1"},
            )
            output = result.stdout + ("\n" + result.stderr if result.stderr else "")
            return output[-8000:]  # Last 8k chars
        except subprocess.TimeoutExpired:
            return "Research run timed out after 20 minutes. Use hive_research_status to check."
        except Exception as e:
            return f"Error starting research: {e}"

    @mcp.tool()
    async def hive_research_status() -> str:
        """Check status of recent hive-research runs.

        Lists the latest research runs with their scores and completion status.
        """
        runs_dir = hive_path / "results" / "runs"
        if not runs_dir.is_dir():
            return "No research runs found."

        runs = sorted(runs_dir.iterdir(), reverse=True)[:10]
        lines = ["Recent research runs:\n"]

        for run_dir in runs:
            if not run_dir.is_dir():
                continue

            name = run_dir.name
            final = run_dir / "07_final_report.md"
            status = "complete" if final.exists() else "in-progress"

            score = "—"
            if final.exists():
                try:
                    content = final.read_text(errors="replace")[:1000]
                    for line in content.split("\n"):
                        if "score" in line.lower() and any(c.isdigit() for c in line):
                            score = line.strip()
                            break
                except Exception:
                    pass

            # Check which steps exist
            steps = len([f for f in run_dir.iterdir() if f.name.startswith("0")])

            lines.append(f"  {name}")
            lines.append(f"    Status: {status} ({steps}/7 steps)")
            lines.append(f"    Score: {score}")
            lines.append("")

        return "\n".join(lines)

    @mcp.tool()
    async def hive_list_mined() -> str:
        """List all mined knowledge outputs."""
        mined_dir = hive_path / "knowledge" / "raw" / "mined"
        if not mined_dir.is_dir():
            return "No mined outputs found."

        files = sorted(mined_dir.glob("*.md"))
        lines = [f"Mined outputs ({len(files)} files):\n"]
        for f in files:
            size_kb = f.stat().st_size / 1024
            lines.append(f"  {f.name} ({size_kb:.0f} KB)")

        return "\n".join(lines)
