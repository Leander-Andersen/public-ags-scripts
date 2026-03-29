#!/usr/bin/env python3
"""
gpt-worker — MCP server that exposes GPT-5.4 as a parallel worker pool for Claude.

Claude (the overseer) calls these tools to delegate grunt work: web research and
document processing. Claude decides how many workers to spin up, evaluates the
results, and calls again with refined inputs if needed. Claude produces the final
structured answer.
"""

import asyncio
import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

# Load .env from same directory as this file
load_dotenv(Path(__file__).parent / ".env")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
GPT_MODEL = os.getenv("GPT_MODEL", "gpt-5.4")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "4000"))
MAX_PARALLEL_REQUESTS = int(os.getenv("MAX_PARALLEL_REQUESTS", "5"))

if not OPENAI_API_KEY:
    raise RuntimeError("OPENAI_API_KEY is not set. Copy .env.example to .env and fill it in.")

import openai  # noqa: E402 — imported after env load so key is available

_client = openai.AsyncOpenAI(api_key=OPENAI_API_KEY)
_sem = asyncio.Semaphore(MAX_PARALLEL_REQUESTS)

mcp = FastMCP("gpt-worker")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_source_sync(source: str) -> str:
    """Load content from a URL, file path, or return raw text as-is."""
    if source.startswith("http://") or source.startswith("https://"):
        import html2text
        import requests
        resp = requests.get(source, timeout=30)
        resp.raise_for_status()
        return html2text.html2text(resp.text)

    path = Path(source)
    if path.exists():
        if path.suffix.lower() == ".pdf":
            import pypdf
            reader = pypdf.PdfReader(str(path))
            return "\n".join(page.extract_text() or "" for page in reader.pages)
        if path.suffix.lower() == ".docx":
            import docx
            doc = docx.Document(str(path))
            return "\n".join(p.text for p in doc.paragraphs)
        return path.read_text(encoding="utf-8")

    # Treat as raw text
    return source


def _chunk_text(text: str, chunk_size: int) -> list[str]:
    """Split text into chunks of roughly chunk_size tokens."""
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    token_ids = enc.encode(text)
    chunks = []
    for i in range(0, len(token_ids), chunk_size):
        chunk_tokens = token_ids[i : i + chunk_size]
        chunks.append(enc.decode(chunk_tokens))
    return chunks if chunks else [text]


# ---------------------------------------------------------------------------
# Low-level async workers
# ---------------------------------------------------------------------------

async def _search_one(query: str, focus: str) -> dict[str, Any]:
    """Fire a single web search via the OpenAI Responses API."""
    async with _sem:
        try:
            response = await _client.responses.create(
                model=GPT_MODEL,
                tools=[{"type": "web_search_preview"}],
                input=(
                    f"Focus on extracting information relevant to: {focus}\n\n"
                    f"Search query: {query}\n\n"
                    "Provide a concise TL;DR of the most relevant findings. "
                    "Include key facts, figures, and source URLs."
                ),
            )
            # Extract text content from the response output
            findings = ""
            sources: list[str] = []
            for item in response.output:
                if getattr(item, "type", None) == "message":
                    for block in item.content:
                        if getattr(block, "type", None) == "output_text":
                            findings += block.text
                            # Collect cited URLs from annotations
                            for ann in getattr(block, "annotations", []):
                                url = getattr(ann, "url", None)
                                if url:
                                    sources.append(url)
            return {"query": query, "findings": findings.strip(), "sources_used": sources}
        except Exception as e:
            return {"query": query, "findings": f"ERROR: {e}", "sources_used": []}


async def _summarize_chunk(chunk: str, focus: str) -> str:
    """Ask GPT to summarize a single document chunk relevant to focus."""
    async with _sem:
        resp = await _client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a precise summarizer. "
                        f"Extract only what is relevant to: {focus}. "
                        "Be concise. Omit anything unrelated."
                    ),
                },
                {"role": "user", "content": chunk},
            ],
        )
        return resp.choices[0].message.content or ""


async def _consolidate(chunk_summaries: list[str], focus: str) -> str:
    """Merge multiple chunk summaries into one coherent summary."""
    if len(chunk_summaries) == 1:
        return chunk_summaries[0]
    combined = "\n\n---\n\n".join(chunk_summaries)
    async with _sem:
        resp = await _client.chat.completions.create(
            model=GPT_MODEL,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are a precise summarizer. "
                        f"Consolidate the following chunk summaries into one coherent summary focused on: {focus}. "
                        "Remove repetition. Be concise."
                    ),
                },
                {"role": "user", "content": combined},
            ],
        )
        return resp.choices[0].message.content or ""


async def _process_one(source: str, focus: str) -> dict[str, Any]:
    """Load a source, chunk it, summarize each chunk, consolidate."""
    try:
        text = await asyncio.to_thread(_load_source_sync, source)
        chunks = _chunk_text(text, CHUNK_SIZE)
        chunk_summaries = await asyncio.gather(*[_summarize_chunk(c, focus) for c in chunks])
        summary = await _consolidate(list(chunk_summaries), focus)
        return {"source": source, "summary": summary, "chunk_count": len(chunks)}
    except Exception as e:
        return {"source": source, "summary": f"ERROR: {e}", "chunk_count": 0}


# ---------------------------------------------------------------------------
# MCP Tools
# ---------------------------------------------------------------------------

@mcp.tool()
async def gpt_search(queries: list[str], focus: str) -> list[dict]:
    """
    Search the web using GPT with built-in web search.

    Pass ALL queries you want to run at once — they are executed in parallel.
    Each query should be a distinct search term or question.

    focus describes what you are ultimately trying to find out, so GPT knows
    what to extract and emphasise in its TL;DR.

    Returns a list of {query, findings, sources_used} — one entry per query.

    Call this tool again with refined or broader queries if the initial results
    are thin, off-topic, or contradict each other. You decide when you have
    enough information.

    Examples of good multi-query calls:
      queries=["GPT-5 release date", "GPT-5 benchmark results", "GPT-5 pricing"]
      focus="Understand GPT-5 capabilities and cost for a purchasing decision"
    """
    results = await asyncio.gather(*[_search_one(q, focus) for q in queries])
    return list(results)


@mcp.tool()
async def gpt_process(sources: list[str], focus: str) -> list[dict]:
    """
    Load and summarize documents or web pages using GPT.

    Accepts a mix of:
      - File paths (.pdf, .docx, .txt, .md, or any plain-text file)
      - URLs (fetched and converted from HTML)
      - Raw text strings (processed directly)

    Each source is chunked by token count, each chunk is summarised with the
    given focus, then chunk summaries are consolidated into a final per-source
    summary. All sources are processed in parallel.

    focus describes what you want GPT to extract — be specific so irrelevant
    content is filtered out during summarisation.

    Returns a list of {source, summary, chunk_count} — one entry per source.

    Call again with a more specific focus if the summaries miss key details,
    or with additional sources if you need broader coverage.

    Examples:
      sources=["/tmp/report.pdf", "https://example.com/article"]
      focus="Find all mentions of budget figures and financial projections"
    """
    results = await asyncio.gather(*[_process_one(s, focus) for s in sources])
    return list(results)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    mcp.run(transport="stdio")
