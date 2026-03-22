"""MCP Tool: Repo Digest — token-efficient codebase analysis.

Provides three levels of codebase insight:
  1. Dependency graph — imports and module relationships (~500 tokens)
  2. Signature map — function/class signatures per file (~3-5k tokens)
  3. File content — full source of specific files (on-demand)
"""

import os
import json
import subprocess
from pathlib import Path

# Language configs for tree-sitter signature extraction
LANG_EXTENSIONS = {
    ".py": "python",
    ".js": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".go": "go",
    ".rs": "rust",
}

# Signature query patterns per language (tree-sitter S-expressions)
SIGNATURE_QUERIES = {
    "python": """
        (function_definition name: (identifier) @name parameters: (parameters) @params) @func
        (class_definition name: (identifier) @name) @cls
    """,
    "javascript": """
        (function_declaration name: (identifier) @name parameters: (formal_parameters) @params) @func
        (class_declaration name: (identifier) @name) @cls
        (export_statement declaration: (function_declaration name: (identifier) @name)) @export
    """,
    "typescript": """
        (function_declaration name: (identifier) @name parameters: (formal_parameters) @params) @func
        (class_declaration name: (identifier) @name) @cls
        (interface_declaration name: (type_identifier) @name) @iface
    """,
    "go": """
        (function_declaration name: (identifier) @name parameters: (parameter_list) @params) @func
        (type_declaration (type_spec name: (type_identifier) @name)) @type
    """,
    "rust": """
        (function_item name: (identifier) @name parameters: (parameters) @params) @func
        (struct_item name: (type_identifier) @name) @struct
        (impl_item type: (type_identifier) @name) @impl
    """,
}


def register(mcp, config: dict):
    """Register repo digest tools with the MCP server."""

    rd_config = config.get("tools", {}).get("repo_digest", {})
    max_files = rd_config.get("max_files", 500)

    @mcp.tool()
    async def repo_tree(path: str, max_depth: int = 3) -> str:
        """Show the directory tree of a repository.

        Args:
            path: Absolute path to the repository root.
            max_depth: Maximum directory depth to show (default: 3).
        """
        if not os.path.isdir(path):
            return f"Error: {path} is not a directory"

        result = subprocess.run(
            ["find", path, "-maxdepth", str(max_depth), "-not", "-path", "*/.*"],
            capture_output=True, text=True, timeout=10,
        )
        lines = sorted(result.stdout.strip().split("\n"))
        # Convert to tree-like format
        root = Path(path)
        tree = []
        for line in lines[:max_files]:
            p = Path(line)
            try:
                rel = p.relative_to(root)
                indent = "  " * len(rel.parts)
                name = rel.name or root.name
                if p.is_dir():
                    name += "/"
                tree.append(f"{indent}{name}")
            except ValueError:
                continue
        return "\n".join(tree)

    @mcp.tool()
    async def repo_signatures(path: str, extensions: list[str] | None = None) -> str:
        """Extract function and class signatures from a repository.

        Returns a compact map of all public APIs/functions/classes per file,
        designed to give maximum code understanding with minimum tokens.

        Args:
            path: Absolute path to the repository root.
            extensions: File extensions to scan (default: .py, .js, .ts, .go, .rs).
        """
        if not os.path.isdir(path):
            return f"Error: {path} is not a directory"

        exts = set(extensions or LANG_EXTENSIONS.keys())
        root = Path(path)
        results = {}

        # Collect source files
        source_files = []
        for ext in exts:
            source_files.extend(root.rglob(f"*{ext}"))

        source_files = [
            f for f in source_files
            if not any(p.startswith(".") for p in f.relative_to(root).parts)
            and "node_modules" not in str(f)
            and "venv" not in str(f)
            and "__pycache__" not in str(f)
        ]
        source_files = source_files[:max_files]

        try:
            import tree_sitter
            return _extract_with_treesitter(root, source_files, tree_sitter)
        except ImportError:
            return _extract_with_regex(root, source_files)

    @mcp.tool()
    async def repo_file(path: str, file: str) -> str:
        """Read a specific file from a repository.

        Args:
            path: Absolute path to the repository root.
            file: Relative path to the file within the repo.
        """
        full = Path(path) / file
        if not full.is_file():
            return f"Error: {full} not found"
        try:
            content = full.read_text(errors="replace")
            lines = content.split("\n")
            numbered = [f"{i+1:4d} | {line}" for i, line in enumerate(lines)]
            return "\n".join(numbered)
        except Exception as e:
            return f"Error reading {file}: {e}"

    @mcp.tool()
    async def repo_deps(path: str) -> str:
        """Analyze dependencies of a repository.

        Detects package manager files and extracts dependency lists.

        Args:
            path: Absolute path to the repository root.
        """
        root = Path(path)
        if not root.is_dir():
            return f"Error: {path} is not a directory"

        deps = {}

        # Python
        for req_file in ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"]:
            p = root / req_file
            if p.exists():
                deps[req_file] = p.read_text(errors="replace")[:2000]

        # Node
        pkg = root / "package.json"
        if pkg.exists():
            try:
                data = json.loads(pkg.read_text())
                deps["package.json"] = {
                    "dependencies": data.get("dependencies", {}),
                    "devDependencies": data.get("devDependencies", {}),
                }
            except json.JSONDecodeError:
                deps["package.json"] = "parse error"

        # Go
        go_mod = root / "go.mod"
        if go_mod.exists():
            deps["go.mod"] = go_mod.read_text(errors="replace")[:2000]

        # Rust
        cargo = root / "Cargo.toml"
        if cargo.exists():
            deps["Cargo.toml"] = cargo.read_text(errors="replace")[:2000]

        if not deps:
            return "No dependency files found."

        return json.dumps(deps, indent=2, default=str)


def _extract_with_treesitter(root, files, ts):
    """Extract signatures using tree-sitter (precise)."""
    results = {}

    for fpath in files:
        ext = fpath.suffix
        lang_name = LANG_EXTENSIONS.get(ext)
        if not lang_name:
            continue

        try:
            lang_mod = __import__(f"tree_sitter_{lang_name.replace('-', '_')}")
            language = ts.Language(lang_mod.language())
            parser = ts.Parser(language)

            source = fpath.read_bytes()
            tree = parser.parse(source)

            sigs = []
            _walk_for_signatures(tree.root_node, source, sigs)

            if sigs:
                rel = str(fpath.relative_to(root))
                results[rel] = sigs
        except Exception:
            continue

    lines = []
    for fname, sigs in sorted(results.items()):
        lines.append(f"\n## {fname}")
        for sig in sigs:
            lines.append(f"  {sig}")

    return "\n".join(lines) if lines else "No signatures extracted."


def _walk_for_signatures(node, source, sigs, depth=0):
    """Walk tree-sitter AST and collect function/class signatures."""
    if node.type in (
        "function_definition", "function_declaration", "function_item",
        "class_definition", "class_declaration", "struct_item",
        "interface_declaration", "type_declaration", "impl_item",
    ):
        line = source[node.start_byte:node.end_byte].decode("utf-8", errors="replace")
        # Take only the first line (signature)
        first_line = line.split("\n")[0].rstrip()
        if len(first_line) > 120:
            first_line = first_line[:117] + "..."
        sigs.append(f"L{node.start_point[0]+1}: {first_line}")

    for child in node.children:
        _walk_for_signatures(child, source, sigs, depth + 1)


def _extract_with_regex(root, files):
    """Fallback: extract signatures with regex (less precise)."""
    import re
    results = {}

    patterns = {
        ".py": re.compile(r"^((?:async )?def \w+\(.*?\)|class \w+.*?:)", re.MULTILINE),
        ".js": re.compile(r"^(?:export\s+)?(?:async\s+)?function\s+\w+|^class\s+\w+", re.MULTILINE),
        ".ts": re.compile(r"^(?:export\s+)?(?:async\s+)?function\s+\w+|^(?:export\s+)?class\s+\w+|^(?:export\s+)?interface\s+\w+", re.MULTILINE),
        ".go": re.compile(r"^func\s+(?:\(\w+\s+\*?\w+\)\s+)?\w+|^type\s+\w+\s+struct", re.MULTILINE),
        ".rs": re.compile(r"^(?:pub\s+)?(?:async\s+)?fn\s+\w+|^(?:pub\s+)?struct\s+\w+|^impl\s+", re.MULTILINE),
    }

    for fpath in files:
        ext = fpath.suffix
        pattern = patterns.get(ext)
        if not pattern:
            continue
        try:
            content = fpath.read_text(errors="replace")
            matches = pattern.findall(content)
            if matches:
                rel = str(fpath.relative_to(root))
                results[rel] = [m.rstrip(":{ ") for m in matches]
        except Exception:
            continue

    lines = []
    for fname, sigs in sorted(results.items()):
        lines.append(f"\n## {fname}")
        for sig in sigs:
            lines.append(f"  {sig}")

    return "\n".join(lines) if lines else "No signatures extracted."
