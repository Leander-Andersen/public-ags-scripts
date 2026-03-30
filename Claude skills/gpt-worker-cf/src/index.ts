/**
 * gpt-worker v3 — Cloudflare Workers MCP server
 *
 * Exposes two MCP tools that let Claude (the overseer) delegate grunt work to
 * GPT as a parallel worker pool. Claude decides strategy, GPT processes, Claude
 * evaluates and iterates until it has enough to produce a final answer.
 *
 * Implements the MCP JSON-RPC protocol directly over HTTP — no framework.
 *
 * ─── Tools ────────────────────────────────────────────────────────────────
 *
 * gpt_search(queries, focus, language?, format?, schema?)
 *   Web search via OpenAI Responses API (web_search_preview).
 *   - queries:  string[]               — all run in parallel
 *   - focus:    string                 — guides what GPT extracts
 *   - language: string                 — optional, e.g. "Norwegian" (default: "English")
 *   - format:   "text" | "json"        — prose or structured output (default: "text")
 *   - schema:   object                 — JSON Schema, required when format="json"
 *   Returns: [{status, query, findings, relevance, sources_used, tokens_used, cached}]
 *   relevance: "high" | "medium" | "low" | "unknown"
 *
 * gpt_process(sources, focus, language?, depth?, format?, schema?)
 *   Load + summarize URLs or raw text via OpenAI Chat Completions.
 *   - sources:  string[]               — URLs or raw text, all in parallel
 *   - focus:    string                 — what to extract
 *   - language: string                 — optional, e.g. "Norwegian" (default: "English")
 *   - depth:    "skim"|"normal"|"detailed" — summarization thoroughness (default: "normal")
 *   - format:   "text" | "json"        — prose or structured output (default: "text")
 *   - schema:   object                 — JSON Schema, required when format="json"
 *   Returns: [{status, source, summary, chunk_count, tokens_used, cached, error?}]
 *   status: "ok" | "fetch_failed" | "empty" | "timeout" | "error"
 *
 * ─── Configuration ────────────────────────────────────────────────────────
 *
 * Secrets (Cloudflare dashboard → Worker → Settings → Variables and Secrets):
 *   OPENAI_API_KEY        — required
 *
 * Vars (wrangler.toml [vars] or Cloudflare dashboard):
 *   GPT_MODEL             — model for all calls         (default: gpt-5.4)
 *   CHUNK_SIZE            — tokens per document chunk   (default: 4000)
 *   MAX_PARALLEL_REQUESTS — max concurrent OpenAI calls (default: 5)
 *
 * ─── Caching ──────────────────────────────────────────────────────────────
 *
 * Results are cached in-memory for 5 minutes. Repeated identical calls within
 * the same Worker instance return cached: true and cost zero tokens.
 */

export interface Env {
  OPENAI_API_KEY: string;
  GPT_MODEL?: string;
  CHUNK_SIZE?: string;
  MAX_PARALLEL_REQUESTS?: string;
}

// ---------------------------------------------------------------------------
// MCP JSON-RPC types
// ---------------------------------------------------------------------------

interface RpcRequest {
  jsonrpc: "2.0";
  id?: string | number | null;
  method: string;
  params?: Record<string, unknown>;
}

interface RpcResponse {
  jsonrpc: "2.0";
  id?: string | number | null;
  result?: unknown;
  error?: { code: number; message: string };
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

interface SearchResult {
  status: "ok" | "error";
  query: string;
  findings: string;
  relevance: "high" | "medium" | "low" | "unknown";
  sources_used: string[];
  tokens_used: number;
  cached: boolean;
  error?: string;
}

interface ProcessResult {
  status: "ok" | "fetch_failed" | "empty" | "timeout" | "error";
  source: string;
  summary: string;
  chunk_count: number;
  tokens_used: number;
  cached: boolean;
  error?: string;
}

// ---------------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------------

const _cache = new Map<string, { value: unknown; ts: number }>();
const CACHE_TTL_MS = 5 * 60 * 1000;

function cacheGet<T>(key: string): T | null {
  const entry = _cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.ts > CACHE_TTL_MS) { _cache.delete(key); return null; }
  return entry.value as T;
}

function cacheSet(key: string, value: unknown): void {
  _cache.set(key, { value, ts: Date.now() });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Strip markdown code fences from a string (e.g. ```json ... ``` → ...) */
function stripFences(s: string): string {
  return s.replace(/^```[a-z]*\n?/i, "").replace(/\n?```$/i, "").trim();
}

/**
 * Recursively inject `additionalProperties: false` into every object in a
 * JSON Schema. OpenAI's structured output API requires this on all objects.
 */
function enforceStrictSchema(schema: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = { ...schema };
  if (result.type === "object") {
    result.additionalProperties = false;
    if (result.properties && typeof result.properties === "object") {
      const props = result.properties as Record<string, unknown>;
      result.properties = Object.fromEntries(
        Object.entries(props).map(([k, v]) => [k, enforceStrictSchema(v as Record<string, unknown>)])
      );
    }
  }
  if (result.type === "array" && result.items && typeof result.items === "object") {
    result.items = enforceStrictSchema(result.items as Record<string, unknown>);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "gpt_search",
    description: [
      "Search the web using GPT with built-in web search.",
      "Pass ALL queries you want to run at once — they execute in parallel.",
      "focus describes what you ultimately want to find so GPT knows what to extract.",
      "language optionally biases results e.g. 'Norwegian', 'English' (default: English).",
      "format='json' + schema returns structured data instead of prose — useful in pipelines.",
      "Call again with refined or broader queries if initial results are thin or off-topic.",
      "Returns [{status, query, findings, relevance, sources_used, tokens_used, cached}].",
      "relevance is high/medium/low — use it to decide whether to dig deeper.",
    ].join(" "),
    inputSchema: {
      type: "object",
      properties: {
        queries: {
          type: "array",
          items: { type: "string" },
          description: "List of search queries to run in parallel",
        },
        focus: {
          type: "string",
          description: "What you ultimately want to find — guides GPT extraction",
        },
        language: {
          type: "string",
          description: "Language bias e.g. 'Norwegian', 'English' (optional, default: English)",
        },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "text = freeform prose, json = structured output (default: text)",
        },
        schema: {
          type: "object",
          description: "JSON Schema for structured output when format=json",
        },
      },
      required: ["queries", "focus"],
    },
  },
  {
    name: "gpt_process",
    description: [
      "Load and summarize URLs or raw text using GPT.",
      "Each source is chunked, summarised per chunk focused on goal, then consolidated.",
      "All sources processed in parallel. Accepts URLs or raw text — paste any size.",
      "language optionally biases summarization e.g. 'Norwegian' (default: English).",
      "depth: skim=fast/brief, normal=balanced, detailed=thorough (default: normal).",
      "format='json' + schema returns structured data — makes output composable in pipelines.",
      "Returns [{status, source, summary, chunk_count, tokens_used, cached, error?}].",
      "status: ok | fetch_failed | empty | timeout | error — never fails silently.",
      "Call again with a more specific focus if summaries miss key details.",
    ].join(" "),
    inputSchema: {
      type: "object",
      properties: {
        sources: {
          type: "array",
          items: { type: "string" },
          description: "List of URLs or raw text strings to process",
        },
        focus: {
          type: "string",
          description: "What to extract — irrelevant content is filtered during summarisation",
        },
        language: {
          type: "string",
          description: "Language bias for summarization e.g. 'Norwegian', 'English' (optional, default: English)",
        },
        depth: {
          type: "string",
          enum: ["skim", "normal", "detailed"],
          description: "skim=fast/brief, normal=balanced, detailed=thorough (default: normal)",
        },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "text = freeform prose, json = structured output (default: text)",
        },
        schema: {
          type: "object",
          description: "JSON Schema for structured output when format=json",
        },
      },
      required: ["sources", "focus"],
    },
  },
];

// ---------------------------------------------------------------------------
// Worker entry point
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/.well-known/")) {
      return new Response("Not Found", { status: 404 });
    }

    // Two modes — add both to claude.ai Settings → Integrations and toggle as needed:
    //   /mcp          Research mode    — gpt_search + gpt_process
    //   /mcp/process  Processing mode  — gpt_process only (no web search tokens spent)
    const isProcessingMode = url.pathname === "/mcp/process";
    const isMcpEndpoint = url.pathname === "/mcp" || isProcessingMode;

    if (isMcpEndpoint) {
      if (request.method === "POST") return handleMcp(request, env, isProcessingMode);
      if (request.method === "GET") {
        const mode = isProcessingMode ? "Processing mode (gpt_process only)" : "Research mode (gpt_search + gpt_process)";
        return new Response(`gpt-worker MCP server — ${mode}. POST to this endpoint.`, {
          status: 200, headers: { "Content-Type": "text/plain" },
        });
      }
      return new Response("Method Not Allowed", { status: 405 });
    }

    return new Response(
      "gpt-worker MCP server\n  /mcp          Research mode    (gpt_search + gpt_process)\n  /mcp/process  Processing mode  (gpt_process only)",
      { status: 200, headers: { "Content-Type": "text/plain" } }
    );
  },
};

// ---------------------------------------------------------------------------
// MCP request handler
// ---------------------------------------------------------------------------

async function handleMcp(request: Request, env: Env, processingMode = false): Promise<Response> {
  let body: RpcRequest | RpcRequest[];
  try {
    body = (await request.json()) as RpcRequest | RpcRequest[];
  } catch {
    return Response.json(
      { jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } },
      { status: 400 }
    );
  }

  const isBatch = Array.isArray(body);
  const requests = isBatch ? (body as RpcRequest[]) : [body as RpcRequest];
  const responses: RpcResponse[] = [];

  for (const req of requests) {
    if (req.id === undefined || req.id === null) continue;
    responses.push(await dispatchRpc(req, env, processingMode));
  }

  if (responses.length === 0) return new Response(null, { status: 204 });

  return Response.json(isBatch ? responses : responses[0], {
    headers: { "Content-Type": "application/json" },
  });
}

async function dispatchRpc(req: RpcRequest, env: Env, processingMode = false): Promise<RpcResponse> {
  const model = env.GPT_MODEL ?? "gpt-5.4";
  const chunkSize = parseInt(env.CHUNK_SIZE ?? "32000", 10);

  try {
    switch (req.method) {
      case "initialize":
        return {
          jsonrpc: "2.0", id: req.id,
          result: {
            protocolVersion: "2025-03-26",
            capabilities: { tools: {} },
            serverInfo: { name: "gpt-worker", version: "3.0.0" },
          },
        };

      case "notifications/initialized":
        return { jsonrpc: "2.0", id: req.id, result: {} };

      case "tools/list":
        return { jsonrpc: "2.0", id: req.id, result: { tools: processingMode ? TOOLS.filter(t => t.name === "gpt_process") : TOOLS } };

      case "tools/call": {
        const { name, arguments: args } = req.params as {
          name: string;
          arguments: Record<string, unknown>;
        };

        if (name === "gpt_search") {
          const result = await gptSearch(
            args.queries as string[],
            args.focus as string,
            (args.language as string) ?? "English",
            (args.format as "text" | "json") ?? "text",
            (args.schema as Record<string, unknown>) ?? null,
            env.OPENAI_API_KEY,
            model,
          );
          return {
            jsonrpc: "2.0", id: req.id,
            result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] },
          };
        }

        if (name === "gpt_process") {
          const result = await gptProcess(
            args.sources as string[],
            args.focus as string,
            (args.language as string) ?? "English",
            (args.depth as "skim" | "normal" | "detailed") ?? "normal",
            (args.format as "text" | "json") ?? "text",
            (args.schema as Record<string, unknown>) ?? null,
            env.OPENAI_API_KEY,
            model,
            chunkSize,
          );
          return {
            jsonrpc: "2.0", id: req.id,
            result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] },
          };
        }

        return {
          jsonrpc: "2.0", id: req.id,
          error: { code: -32601, message: `Unknown tool: ${name}` },
        };
      }

      default:
        return {
          jsonrpc: "2.0", id: req.id,
          error: { code: -32601, message: `Method not found: ${req.method}` },
        };
    }
  } catch (e) {
    return {
      jsonrpc: "2.0", id: req.id,
      error: { code: -32603, message: String(e) },
    };
  }
}

// ---------------------------------------------------------------------------
// gpt_search implementation
// ---------------------------------------------------------------------------

async function gptSearch(
  queries: string[],
  focus: string,
  language: string,
  format: "text" | "json",
  schema: Record<string, unknown> | null,
  apiKey: string,
  model: string,
): Promise<SearchResult[]> {
  const schemaInstruction = format === "json" && schema
    ? `Return ONLY valid JSON matching this schema (no markdown fences): ${JSON.stringify(schema)}`
    : "";

  return Promise.all(
    queries.map(async (query): Promise<SearchResult> => {
        const cacheKey = `search:${model}:${language}:${format}:${focus}:${query}`;
        const hit = cacheGet<SearchResult>(cacheKey);
        if (hit) return { ...hit, cached: true };

        try {
          const resp = await fetch("https://api.openai.com/v1/responses", {
            method: "POST",
            headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              model,
              tools: [{ type: "web_search_preview" }],
              input: [
                `You are a research assistant. Language preference: ${language}.`,
                `Focus goal: ${focus}`,
                `Search query: ${query}`,
                format === "json" && schema
                  ? schemaInstruction
                  : "Return a concise TL;DR of the most relevant findings.",
                `End your response with a relevance rating on its own line: RELEVANCE: high | medium | low`,
                `Briefly explain why.`,
              ].filter(Boolean).join("\n\n"),
            }),
          });

          if (!resp.ok) throw new Error(`OpenAI ${resp.status}: ${await resp.text()}`);

          const data = (await resp.json()) as {
            usage?: { total_tokens?: number };
            output: Array<{
              type: string;
              content?: Array<{
                type: string;
                text?: string;
                annotations?: Array<{ url?: string }>;
              }>;
            }>;
          };

          let rawFindings = "";
          const sources: string[] = [];

          for (const item of data.output ?? []) {
            if (item.type === "message") {
              for (const block of item.content ?? []) {
                if (block.type === "output_text" && block.text) {
                  rawFindings += block.text;
                  for (const ann of block.annotations ?? []) {
                    if (ann.url) sources.push(ann.url);
                  }
                }
              }
            }
          }

          let relevance: "high" | "medium" | "low" | "unknown" = "unknown";
          let findings = rawFindings.trim();
          const relevanceMatch = findings.match(/RELEVANCE:\s*(high|medium|low)/i);
          if (relevanceMatch) {
            relevance = relevanceMatch[1].toLowerCase() as "high" | "medium" | "low";
            findings = findings.replace(/RELEVANCE:\s*(high|medium|low)/i, `[Relevance: ${relevance}]`).trim();
          }

          if (format === "json") findings = stripFences(findings);

          const result: SearchResult = {
            status: "ok",
            query,
            findings,
            relevance,
            sources_used: sources,
            tokens_used: data.usage?.total_tokens ?? 0,
            cached: false,
          };

          cacheSet(cacheKey, result);
          return result;
        } catch (e) {
          return {
            status: "error",
            query,
            findings: "",
            relevance: "unknown",
            sources_used: [],
            tokens_used: 0,
            cached: false,
            error: String(e),
          };
        }
      })
  );
}

// ---------------------------------------------------------------------------
// gpt_process implementation
// ---------------------------------------------------------------------------

async function gptProcess(
  sources: string[],
  focus: string,
  language: string,
  depth: "skim" | "normal" | "detailed",
  format: "text" | "json",
  schema: Record<string, unknown> | null,
  apiKey: string,
  model: string,
  chunkSize: number,
): Promise<ProcessResult[]> {
  const depthPrompts = {
    skim: {
      chunk: `You are a fast summarizer. Language: ${language}. Give a brief 2-3 sentence summary of what is relevant to: ${focus}. Be extremely concise.`,
      consolidate: `Combine these brief summaries into one short paragraph focused on: ${focus}. Language: ${language}.`,
      maxTokens: 512,
    },
    normal: {
      chunk: `You are a precise summarizer. Language: ${language}. Extract the key points relevant to: ${focus}. Be concise but complete.`,
      consolidate: `Consolidate these summaries into a clear, well-structured summary focused on: ${focus}. Language: ${language}. Remove repetition.`,
      maxTokens: 2048,
    },
    detailed: {
      chunk: `You are a precise analyst. Language: ${language}. Extract ALL details relevant to: ${focus}. Include specifics, numbers, names, dates. Omit only clearly unrelated content.`,
      consolidate: `Consolidate these detailed summaries into one comprehensive summary focused on: ${focus}. Language: ${language}. Preserve all important details. Remove only repetition.`,
      maxTokens: 8192,
    },
  };

  const dp = depthPrompts[depth];

  return Promise.all(
    sources.map(async (source): Promise<ProcessResult> => {
        const cacheKey = `process:${model}:${language}:${depth}:${format}:${focus}:${source.slice(0, 200)}`;
        const hit = cacheGet<ProcessResult>(cacheKey);
        if (hit) return { ...hit, cached: true };

        const sourceLabel = source.startsWith("http") ? source : source.slice(0, 80) + (source.length > 80 ? "…" : "");

        try {
          let text: string;

          if (source.startsWith("http://") || source.startsWith("https://")) {
            let resp: Response;
            try {
              resp = await fetch(source, {
                headers: { "User-Agent": "gpt-worker-mcp/1.0" },
                signal: AbortSignal.timeout(15000),
              });
            } catch (e) {
              const isTimeout = String(e).includes("timeout") || String(e).includes("TimeoutError");
              return { status: isTimeout ? "timeout" : "fetch_failed", source: sourceLabel, summary: "", chunk_count: 0, tokens_used: 0, cached: false, error: String(e) };
            }
            if (!resp.ok) {
              return { status: "fetch_failed", source: sourceLabel, summary: "", chunk_count: 0, tokens_used: 0, cached: false, error: `HTTP ${resp.status}` };
            }
            const ct = resp.headers.get("content-type") ?? "";
            const raw = await resp.text();
            text = ct.includes("html") ? raw.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim() : raw;
          } else {
            text = source;
          }

          if (!text.trim()) {
            return { status: "empty", source: sourceLabel, summary: "", chunk_count: 0, tokens_used: 0, cached: false, error: "Source produced no text content" };
          }

          const chunkChars = chunkSize * 4;
          const chunks: string[] = [];
          for (let j = 0; j < text.length; j += chunkChars) chunks.push(text.slice(j, j + chunkChars));

          let totalTokens = 0;

          const chat = async (messages: Array<{ role: string; content: string }>, useSchema = false) => {
            const body: Record<string, unknown> = { model, messages, max_completion_tokens: dp.maxTokens };
            if (useSchema && schema) {
              body.response_format = { type: "json_schema", json_schema: { name: "output", schema: enforceStrictSchema(schema), strict: true } };
            }
            const r = await fetch("https://api.openai.com/v1/chat/completions", {
              method: "POST",
              headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
              body: JSON.stringify(body),
            });
            if (!r.ok) throw new Error(`OpenAI ${r.status}: ${await r.text()}`);
            const d = (await r.json()) as {
              usage?: { total_tokens?: number };
              choices: Array<{ message: { content: string } }>;
            };
            totalTokens += d.usage?.total_tokens ?? 0;
            return d.choices[0].message.content ?? "";
          };

          const chunkSummaries = await Promise.all(
            chunks.map((chunk) => chat([
              { role: "system", content: dp.chunk },
              { role: "user", content: chunk },
            ]))
          );

          const finalSystemPrompt = format === "json" && schema
            ? `${dp.consolidate} Return ONLY valid JSON matching this schema (no markdown fences): ${JSON.stringify(schema)}`
            : dp.consolidate;

          const rawSummary = chunkSummaries.length === 1
            ? (format === "json" ? await chat([
                { role: "system", content: finalSystemPrompt },
                { role: "user", content: chunkSummaries[0] },
              ], true) : chunkSummaries[0])
            : await chat([
                { role: "system", content: finalSystemPrompt },
                { role: "user", content: chunkSummaries.join("\n\n---\n\n") },
              ], format === "json");

          const summary = format === "json" ? stripFences(rawSummary) : rawSummary;

          if (!summary.trim()) {
            return { status: "empty", source: sourceLabel, summary: "", chunk_count: chunks.length, tokens_used: totalTokens, cached: false, error: "GPT returned empty content — likely hit token limit on a large chunk" };
          }

          const result: ProcessResult = {
            status: "ok",
            source: sourceLabel,
            summary,
            chunk_count: chunks.length,
            tokens_used: totalTokens,
            cached: false,
          };

          cacheSet(cacheKey, result);
          return result;
        } catch (e) {
          return {
            status: "error",
            source: sourceLabel,
            summary: "",
            chunk_count: 0,
            tokens_used: 0,
            cached: false,
            error: String(e),
          };
        }
      })
  );
}
