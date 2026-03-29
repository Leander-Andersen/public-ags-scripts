# gpt-worker-cf — GPT-5.4 worker bridge for claude.ai (Cloudflare Workers)

MCP server hosted on Cloudflare Workers. Claude in the browser calls this when it needs to do something it can't natively — web research or processing large amounts of text/documents — delegating the grunt work to GPT-5.4.

Same two tools as the Python version (`gpt_search`, `gpt_process`), same agentic loop. Claude decides the strategy, GPT does the grunt work, Claude structures the final answer.

> For local Claude Code use, see [../gpt-worker](../gpt-worker/README.md) (Python, stdio).

## How it works

```
You (claude.ai browser or app)
    ↓
Claude decides strategy, calls MCP tools
    ↓
Cloudflare Worker (this code, always-on public URL)
    ↓  parallel requests
  GPT-5.4 (web search / document processing)
    ↓
TL;DRs returned to Claude
    ↓
Claude evaluates → iterates if needed → final structured answer
```

You can paste 100k+ lines of text directly in the chat — Claude will pass it to `gpt_process` in chunks automatically.

## Deploy (no terminal needed)

**1. Connect repo to Cloudflare**

1. Go to [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages → Create**
2. Choose **Connect to Git** → connect your GitHub account
3. Select the `public-ags-scripts` repository
4. Set **Root Directory** to `Claude skills/gpt-worker-cf`
5. Cloudflare detects `package.json` + `wrangler.toml` and builds automatically
6. Click **Deploy**

**2. Set your OpenAI API key**

In the Worker's settings page:
**Settings → Variables and Secrets → Add Secret**
- Name: `OPENAI_API_KEY`
- Value: your OpenAI API key

**3. Add to claude.ai**

1. Copy your Worker URL from the Cloudflare dashboard (e.g. `https://gpt-worker-mcp.yourname.workers.dev`)
2. Go to **claude.ai → Settings → Integrations → Add integration**
3. Enter: `https://gpt-worker-mcp.yourname.workers.dev/mcp`
4. Save

The `gpt_search` and `gpt_process` tools will now be available in any claude.ai conversation.

## Configuration

Non-secret config is set in `wrangler.toml` under `[vars]`. Edit the file, push to GitHub, and Cloudflare redeploys automatically.

| Variable | Default | Description |
|----------|---------|-------------|
| `GPT_MODEL` | `gpt-5.4` | Model used for all GPT calls |
| `CHUNK_SIZE` | `4000` | Approx tokens per document chunk |
| `MAX_PARALLEL_REQUESTS` | `5` | Max concurrent OpenAI requests |

`OPENAI_API_KEY` must always be set as a secret in the Cloudflare dashboard, never in `wrangler.toml`.

## Tools

### `gpt_search(queries, focus)`
Searches the web in parallel using GPT's built-in web search. Claude decides how many queries to fire and what to search for. Iterates automatically with refined queries if initial results are insufficient.

### `gpt_process(sources, focus)`
Processes URLs or raw text. Chunks the content, GPT summarises each chunk focused on your goal, then consolidates into a per-source summary. All sources processed in parallel.

Accepts:
- URLs (fetched automatically)
- Raw text — paste directly, any size

> Note: local file paths are not supported in the Workers version (no filesystem). Use URLs or paste text directly.

## Troubleshooting

**Tools not showing in claude.ai** — Make sure you added `/mcp` at the end of the URL.

**`web_search_preview` not available** — Your OpenAI account may not have Responses API access yet. Check your OpenAI dashboard.

**Rate limit errors from OpenAI** — Lower `MAX_PARALLEL_REQUESTS` in `wrangler.toml`, push, Cloudflare redeploys.

**Build fails on Cloudflare** — Check that the root directory is set to `Claude skills/gpt-worker-cf` exactly (note the space).

**Durable Object migration error on first deploy** — Trigger a second deploy from the Cloudflare dashboard; first-time migrations occasionally need two passes.
