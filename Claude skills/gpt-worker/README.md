# gpt-worker — GPT-5.4 worker bridge for Claude

Exposes GPT-5.4 as a parallel worker pool via MCP. Claude (the overseer) delegates web research and document processing to GPT, evaluates the TL;DR results, and iterates until it has enough information to produce a final structured answer.

## How it works

```
User query → Claude decides strategy
    → Calls gpt_search / gpt_process with N inputs
    → GPT-5.4 processes all inputs in parallel
    → Returns TL;DRs to Claude
    → Claude evaluates: enough? → iterate or finalize
    → Claude produces structured final answer
```

## Quick start

**1. Install dependencies**

```bash
cd "<SCRIPT_FOLDER>/Claude skills/gpt-worker"
pip install -r requirements.txt
```

**2. Configure API key**

```bash
cp .env.example .env
```

Edit `.env` and set your `OPENAI_API_KEY`. All other values have sensible defaults.

**3. Add to Claude Code**

Add the following to `~/.claude.json` under `"mcpServers"`:

```json
{
  "mcpServers": {
    "gpt-worker": {
      "command": "python",
      "args": ["<SCRIPT_FOLDER>/Claude skills/gpt-worker/server.py"]
    }
  }
}
```

Restart Claude Code. Confirm the tools are available by running `/mcp` in the chat.

## Tools

### `gpt_search(queries, focus)`

Searches the web using GPT's built-in web search. All queries run in parallel.

| Parameter | Description |
|-----------|-------------|
| `queries` | List of search terms or questions to run simultaneously |
| `focus`   | What you ultimately want to find — guides GPT's extraction |

Returns `[{query, findings, sources_used}, ...]`

### `gpt_process(sources, focus)`

Loads and summarises documents or web pages. All sources processed in parallel.

| Parameter | Description |
|-----------|-------------|
| `sources` | List of file paths (PDF/DOCX/TXT), URLs, or raw text strings |
| `focus`   | What to extract — irrelevant content is filtered during summarisation |

Returns `[{source, summary, chunk_count}, ...]`

Supported file types: `.pdf`, `.docx`, `.txt`, `.md`, any plain-text file, and any HTTP/HTTPS URL.

## Configuration (`.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENAI_API_KEY` | *(required)* | Your OpenAI API key |
| `GPT_MODEL` | `gpt-5.4` | Model used for all GPT calls |
| `CHUNK_SIZE` | `4000` | Tokens per document chunk |
| `MAX_PARALLEL_REQUESTS` | `5` | Max concurrent OpenAI requests |

## Notes

- `gpt_search` uses the OpenAI Responses API (`client.responses.create`) — the only endpoint that supports built-in web search. Requires `openai>=1.30.0`.
- `gpt_process` uses Chat Completions for document summarisation.
- Claude drives the iteration loop — if results are insufficient it will call the tools again with refined queries automatically.
- The `.env` file is gitignored and never committed. Do not hardcode API keys.

## Troubleshooting

**Rate limit errors** — Lower `MAX_PARALLEL_REQUESTS` in `.env` (try `2` or `3`).

**`web_search_preview` not available** — Your OpenAI account may not have access to the Responses API yet. Check your OpenAI dashboard.

**PDF text extraction is empty** — Some PDFs are image-based scans. Consider pre-processing with OCR before passing to `gpt_process`.

**`GPT_MODEL` not found** — The model string in `.env` does not match a model your account has access to. Update `GPT_MODEL` to a model you can use (e.g. `gpt-4o`).
