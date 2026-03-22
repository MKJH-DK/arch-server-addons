"""MCP Tool: Ollama — query local LLM models via Ollama API."""

import httpx


def register(mcp, config: dict):
    """Register Ollama tools with the MCP server."""

    ollama_config = config.get("tools", {}).get("ollama", {})
    base_url = ollama_config.get("url", "http://127.0.0.1:11434")

    @mcp.tool()
    async def ollama_generate(prompt: str, model: str = "llama3.1", system: str = "") -> str:
        """Generate a response from a local Ollama model.

        Args:
            prompt: The prompt to send to the model.
            model: Ollama model name (default: llama3.1).
            system: Optional system prompt.
        """
        payload = {"model": model, "prompt": prompt, "stream": False}
        if system:
            payload["system"] = system

        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(f"{base_url}/api/generate", json=payload)
            resp.raise_for_status()
            return resp.json().get("response", "")

    @mcp.tool()
    async def ollama_chat(messages: list[dict], model: str = "llama3.1") -> str:
        """Chat with a local Ollama model.

        Args:
            messages: List of chat messages [{"role": "user", "content": "..."}].
            model: Ollama model name (default: llama3.1).
        """
        async with httpx.AsyncClient(timeout=120) as client:
            resp = await client.post(
                f"{base_url}/api/chat",
                json={"model": model, "messages": messages, "stream": False},
            )
            resp.raise_for_status()
            return resp.json().get("message", {}).get("content", "")

    @mcp.tool()
    async def ollama_list_models() -> str:
        """List all locally available Ollama models."""
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(f"{base_url}/api/tags")
            resp.raise_for_status()
            models = resp.json().get("models", [])
            lines = []
            for m in models:
                size_gb = m.get("size", 0) / 1e9
                lines.append(f"  {m['name']} ({size_gb:.1f} GB)")
            return "Available models:\n" + "\n".join(lines) if lines else "No models installed."

    @mcp.tool()
    async def ollama_embeddings(text: str, model: str = "nomic-embed-text") -> list[float]:
        """Generate embeddings for text using a local Ollama model.

        Args:
            text: Text to embed.
            model: Embedding model name (default: nomic-embed-text).
        """
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{base_url}/api/embeddings",
                json={"model": model, "prompt": text},
            )
            resp.raise_for_status()
            return resp.json().get("embedding", [])
