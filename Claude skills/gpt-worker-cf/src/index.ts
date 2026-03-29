/**
 * gpt-worker v2 — Cloudflare Workers MCP server
 *
 * Exposes two MCP tools that let Claude (the overseer) delegate grunt work to
 * GPT as a parallel worker pool. Claude decides strategy, GPT processes, Claude
 * evaluates and iterates until it has enough to produce a final answer.
 *
 * Implements the MCP JSON-RPC protocol directly over HTTP — no framework.
 *
 * ─── Tools ────────────────────────────────────────────────────────────────
 *
 * gpt_search(queries, focus, language?)
 *   Web search via OpenAI Responses API (web_search_preview).
 *   - queries:  string[]  — all run in parallel
 *   - focus:    string    — guides what GPT extracts
 *   - language: string    — optional, e.g. "Norwegian" (default: "English")
 *   Returns: [{status, query, findings, relevance, sources_used, tokens_used, cached}]
 *   relevance: "high" | "medium" | "low" | "unknown"
 *
 * gpt_process(sources, focus, depth?, format?, json_schema?)
 *   Load + summarize URLs or raw text via OpenAI Chat Completions.
 *   - sources:     string[]                — URLs or raw text, all in parallel
 *   - focus:       string                  — what to extract
 *   - depth:       "skim" | "detailed"     — brief vs thorough (default: "detailed")
 *   - format:      "text" | "json"         — prose or structured output (default: "text")
 *   - json_schema: object                  — required when format="json"
 *   Returns: [{status, source, summary, chunk_count, tokens_used, cached}]
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
}

interface ProcessResult {
  status: "ok" | "error";
  source: string;
  summary: string;
  chunk_count: number;
  tokens_used: number;
  cached: boolean;
}

// ---------------------------------------------------------------------------
// Simple in-request cache (deduplicates repeated calls within one invocation)
// ---------------------------------------------------------------------------

const _cache = new Map<string, { value: unknown; ts: number }>();
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes

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
// Tool definitions
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "gpt_search",
    description: [
      "Search the web using GPT with built-in web search.",
      "Pass ALL queries you want to run at once — they execute in parallel.",
      "focus describes what you ultimately want to find so GPT knows what to extract.",
      "language optionally biases results (e.g. 'Norwegian', 'English') — defaults to English.",
      "Call again with refined or broader queries if initial results are thin or off-topic.",
      "Returns an array of {status, query, findings, relevance, sources_used, tokens_used, cached}.",
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
          description: "Language bias for search results e.g. 'Norwegian', 'English' (optional, defaults to English)",
        },
      },
      required: ["queries", "focus"],
    },
  },
  {
    name: "gpt_process",
    description: [
      "Load and summarize URLs or raw text using GPT.",
      "Each source is chunked, each chunk summarised with the given focus, then consolidated.",
      "All sources processed in parallel.",
      "Accepts URLs (fetched automatically) or raw text strings — paste any size.",
      "depth controls summarization: 'skim' = fast/brief, 'detailed' = thorough (default: 'detailed').",
      "format controls output: 'text' = freeform summary, 'json' = structured (requires json_schema).",
      "Returns an array of {status, source, summary, chunk_count, tokens_used, cached}.",
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
        depth: {
          type: "string",
          enum: ["skim", "detailed"],
          description: "skim = fast brief summary, detailed = thorough extraction (default: detailed)",
        },
        format: {
          type: "string",
          enum: ["text", "json"],
          description: "text = freeform prose, json = structured output (default: text)",
        },
        json_schema: {
          type: "object",
          description: "JSON schema for structured output when format=json. E.g. {type:'object', properties:{name:{type:'string'}, ...}}",
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

    if (url.pathname === "/mcp") {
      if (request.method === "POST") return handleMcp(request, env);
      if (request.method === "GET") {
        return new Response("gpt-worker MCP server is running. POST to this endpoint.", {
          status: 200, headers: { "Content-Type": "text/plain" },
        });
      }
      return new Response("Method Not Allowed", { status: 405 });
    }

    return new Response("gpt-worker MCP server — POST to /mcp", {
      status: 200, headers: { "Content-Type": "text/plain" },
    });
  },
};

// ---------------------------------------------------------------------------
// MCP request handler
// ---------------------------------------------------------------------------

async function handleMcp(request: Request, env: Env): Promise<Response> {
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
    responses.push(await dispatchRpc(req, env));
  }

  if (responses.length === 0) return new Response(null, { status: 204 });

  return Response.json(isBatch ? responses : responses[0], {
    headers: { "Content-Type": "application/json" },
  });
}

async function dispatchRpc(req: RpcRequest, env: Env): Promise<RpcResponse> {
  const model = env.GPT_MODEL ?? "gpt-5.4";
  const chunkSize = parseInt(env.CHUNK_SIZE ?? "4000", 10);
  const maxParallel = parseInt(env.MAX_PARALLEL_REQUESTS ?? "5", 10);

  try {
    switch (req.method) {
      case "initialize":
        return {
          jsonrpc: "2.0", id: req.id,
          result: {
            protocolVersion: "2025-03-26",
            capabilities: { tools: {} },
            serverInfo: { name: "gpt-worker", version: "2.0.0" },
          },
        };

      case "notifications/initialized":
        return { jsonrpc: "2.0", id: req.id, result: {} };

      case "tools/list":
        return { jsonrpc: "2.0", id: req.id, result: { tools: TOOLS } };

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
            env.OPENAI_API_KEY,
            model,
            maxParallel
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
            (args.depth as "skim" | "detailed") ?? "detailed",
            (args.format as "text" | "json") ?? "text",
            (args.json_schema as Record<string, unknown>) ?? null,
            env.OPENAI_API_KEY,
            model,
            chunkSize,
            maxParallel
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
  apiKey: string,
  model: string,
  maxParallel: number
): Promise<SearchResult[]> {
  const results: SearchResult[] = [];

  for (let i = 0; i < queries.length; i += maxParallel) {
    const batch = queries.slice(i, i + maxParallel);
    const batchResults = await Promise.all(
      batch.map(async (query): Promise<SearchResult> => {
        const cacheKey = `search:${model}:${language}:${focus}:${query}`;
        const cached = cacheGet<SearchResult>(cacheKey);
        if (cached) return { ...cached, cached: true };

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
                `Return a concise TL;DR of the most relevant findings.`,
                `End your response with a relevance rating on its own line: RELEVANCE: high | medium | low`,
                `Explain briefly why you chose that rating.`,
              ].join("\n\n"),
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
                annotations?: Array<{ type?: string; url?: string; title?: string }>;
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

          // Extract relevance rating from the end of the response
          let relevance: "high" | "medium" | "low" | "unknown" = "unknown";
          let findings = rawFindings.trim();
          const relevanceMatch = findings.match(/RELEVANCE:\s*(high|medium|low)/i);
          if (relevanceMatch) {
            relevance = relevanceMatch[1].toLowerCase() as "high" | "medium" | "low";
            // Keep the relevance explanation but mark it clearly
            findings = findings.replace(/RELEVANCE:\s*(high|medium|low)/i, `[Relevance: ${relevance}]`).trim();
          }

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
            findings: String(e),
            relevance: "unknown",
            sources_used: [],
            tokens_used: 0,
            cached: false,
          };
        }
      })
    );
    results.push(...batchResults);
  }

  return results;
}

// ---------------------------------------------------------------------------
// gpt_process implementation
// ---------------------------------------------------------------------------

async function gptProcess(
  sources: string[],
  focus: string,
  depth: "skim" | "detailed",
  format: "text" | "json",
  jsonSchema: Record<string, unknown> | null,
  apiKey: string,
  model: string,
  chunkSize: number,
  maxParallel: number
): Promise<ProcessResult[]> {
  const results: ProcessResult[] = [];

  const systemPrompt = depth === "skim"
    ? `You are a fast summarizer. Give a brief 2-3 sentence summary of what is relevant to: ${focus}. Be extremely concise.`
    : `You are a precise analyst. Extract all details relevant to: ${focus}. Include specifics, numbers, names, dates. Omit only clearly unrelated content.`;

  const consolidatePrompt = depth === "skim"
    ? `Combine these brief summaries into one short paragraph focused on: ${focus}.`
    : `Consolidate these detailed summaries into one comprehensive summary focused on: ${focus}. Preserve all important details. Remove only repetition.`;

  for (let i = 0; i < sources.length; i += maxParallel) {
    const batch = sources.slice(i, i + maxParallel);
    const batchResults = await Promise.all(
      batch.map(async (source): Promise<ProcessResult> => {
        const cacheKey = `process:${model}:${depth}:${format}:${focus}:${source.slice(0, 200)}`;
        const cached = cacheGet<ProcessResult>(cacheKey);
        if (cached) return { ...cached, cached: true };

        try {
          let text: string;

          if (source.startsWith("http://") || source.startsWith("https://")) {
            const resp = await fetch(source, { headers: { "User-Agent": "gpt-worker-mcp/1.0" } });
            if (!resp.ok) throw new Error(`HTTP ${resp.status} fetching ${source}`);
            const ct = resp.headers.get("content-type") ?? "";
            const raw = await resp.text();
            text = ct.includes("html") ? raw.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim() : raw;
          } else {
            text = source;
          }

          const chunkChars = chunkSize * 4;
          const chunks: string[] = [];
          for (let j = 0; j < text.length; j += chunkChars) chunks.push(text.slice(j, j + chunkChars));
          if (chunks.length === 0) chunks.push(text);

          let totalTokens = 0;

          const chat = async (messages: Array<{ role: string; content: string }>, useJsonSchema = false) => {
            const body: Record<string, unknown> = { model, messages, max_completion_tokens: depth === "skim" ? 256 : 1024 };
            if (useJsonSchema && jsonSchema) {
              body.response_format = { type: "json_schema", json_schema: { name: "output", schema: jsonSchema, strict: true } };
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

          // For json format, only apply schema on the final consolidation step
          const chunkSummaries = await Promise.all(
            chunks.map((chunk) => chat([
              { role: "system", content: systemPrompt },
              { role: "user", content: chunk },
            ]))
          );

          const summary = chunkSummaries.length === 1
            ? (format === "json" ? await chat([
                { role: "system", content: `${consolidatePrompt} Return valid JSON matching the requested schema.` },
                { role: "user", content: chunkSummaries[0] },
              ], true)
              : chunkSummaries[0])
            : await chat([
                { role: "system", content: format === "json"
                  ? `${consolidatePrompt} Return valid JSON matching the requested schema.`
                  : consolidatePrompt },
                { role: "user", content: chunkSummaries.join("\n\n---\n\n") },
              ], format === "json");

          const result: ProcessResult = {
            status: "ok",
            source: source.startsWith("http") ? source : source.slice(0, 80) + (source.length > 80 ? "…" : ""),
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
            source: source.startsWith("http") ? source : source.slice(0, 80),
            summary: String(e),
            chunk_count: 0,
            tokens_used: 0,
            cached: false,
          };
        }
      })
    );
    results.push(...batchResults);
  }

  return results;
}
