"""MCP Tool: Knowledge Feed — search the local AI/Python knowledge base."""

import os
import re
from pathlib import Path


def register(mcp, config: dict):
    """Register knowledge feed tools with the MCP server."""

    kf_config = config.get("tools", {}).get("knowledge_feed", {})
    knowledge_path = Path(kf_config.get("path", "/srv/vault/02-knowledge"))

    @mcp.tool()
    async def knowledge_search(query: str, max_results: int = 10) -> str:
        """Search the knowledge base for AI, Python, and tech topics.

        Searches across all markdown files in the knowledge directory.

        Args:
            query: Search terms (space-separated, all must match).
            max_results: Maximum number of results to return (default: 10).
        """
        if not knowledge_path.is_dir():
            return f"Error: Knowledge path {knowledge_path} not found"

        terms = query.lower().split()
        if not terms:
            return "Error: Empty query"

        matches = []
        for md_file in knowledge_path.rglob("*.md"):
            try:
                content = md_file.read_text(errors="replace").lower()
                if all(t in content for t in terms):
                    # Extract a relevant snippet
                    snippet = _extract_snippet(content, terms)
                    rel = str(md_file.relative_to(knowledge_path))
                    matches.append({"file": rel, "snippet": snippet})
            except Exception:
                continue

        if not matches:
            return f"No results for: {query}"

        matches = matches[:max_results]
        lines = [f"Found {len(matches)} result(s) for '{query}':\n"]
        for m in matches:
            lines.append(f"### {m['file']}")
            lines.append(m["snippet"])
            lines.append("")

        return "\n".join(lines)

    @mcp.tool()
    async def knowledge_list(subdirectory: str = "") -> str:
        """List files in the knowledge base.

        Args:
            subdirectory: Optional subdirectory to list (e.g., "01-ai").
        """
        target = knowledge_path / subdirectory if subdirectory else knowledge_path
        if not target.is_dir():
            return f"Error: {target} not found"

        files = []
        for item in sorted(target.rglob("*.md")):
            rel = str(item.relative_to(knowledge_path))
            size_kb = item.stat().st_size / 1024
            files.append(f"  {rel} ({size_kb:.0f} KB)")

        return f"Knowledge base ({len(files)} files):\n" + "\n".join(files)

    @mcp.tool()
    async def knowledge_read(file: str) -> str:
        """Read a specific file from the knowledge base.

        Args:
            file: Relative path within the knowledge directory.
        """
        target = knowledge_path / file
        if not target.is_file():
            return f"Error: {target} not found"

        # Prevent path traversal
        try:
            target.resolve().relative_to(knowledge_path.resolve())
        except ValueError:
            return "Error: Path traversal not allowed"

        content = target.read_text(errors="replace")
        if len(content) > 50_000:
            content = content[:50_000] + "\n\n... (truncated)"
        return content


def _extract_snippet(content: str, terms: list[str], context_chars: int = 300) -> str:
    """Extract a text snippet around the first occurrence of query terms."""
    best_pos = len(content)
    for term in terms:
        pos = content.find(term)
        if pos != -1 and pos < best_pos:
            best_pos = pos

    start = max(0, best_pos - context_chars // 2)
    end = min(len(content), best_pos + context_chars // 2)

    snippet = content[start:end].strip()
    if start > 0:
        snippet = "..." + snippet
    if end < len(content):
        snippet = snippet + "..."

    return snippet
