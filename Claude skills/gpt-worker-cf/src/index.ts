/**
 * gpt-worker — Cloudflare Workers MCP server
 *
 * Implements the MCP JSON-RPC protocol directly over HTTP.
 * No agents/SDK framework dependency — just a fetch handler.
 *
 * Secrets (set via Cloudflare dashboard → Worker → Settings → Variables):
 *   OPENAI_API_KEY — required
 *
 * Vars (wrangler.toml [vars]):
 *   GPT_MODEL              default: gpt-5.4
 *   CHUNK_SIZE             default: 4000
 *   MAX_PARALLEL_REQUESTS  default: 5
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
// Tool definitions (served to claude.ai on tools/list)
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "gpt_search",
    description: [
      "Search the web using GPT with built-in web search.",
      "Pass ALL queries you want to run at once — they execute in parallel.",
      "focus describes what you ultimately want to find so GPT knows what to extract.",
      "Call again with refined or broader queries if initial results are thin or off-topic.",
      "Returns an array of {query, findings, sources_used}.",
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
      "Returns an array of {source, summary, chunk_count}.",
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

    // OAuth discovery endpoints — return 404 to signal no auth required
    if (url.pathname.startsWith("/.well-known/")) {
      return new Response("Not Found", { status: 404 });
    }

    // MCP endpoint
    if (url.pathname === "/mcp") {
      if (request.method === "POST") {
        return handleMcp(request, env);
      }
      if (request.method === "GET") {
        return new Response("gpt-worker MCP server is running. POST to this endpoint.", {
          status: 200,
          headers: { "Content-Type": "text/plain" },
        });
      }
      return new Response("Method Not Allowed", { status: 405 });
    }

    return new Response("gpt-worker MCP server — POST to /mcp", {
      status: 200,
      headers: { "Content-Type": "text/plain" },
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
    // Notifications (no id) do not get a response
    if (req.id === undefined || req.id === null) {
      continue;
    }
    responses.push(await dispatchRpc(req, env));
  }

  if (responses.length === 0) {
    return new Response(null, { status: 204 });
  }

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
          jsonrpc: "2.0",
          id: req.id,
          result: {
            protocolVersion: "2025-03-26",
            capabilities: { tools: {} },
            serverInfo: { name: "gpt-worker", version: "1.0.0" },
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
            env.OPENAI_API_KEY,
            model,
            maxParallel
          );
          return {
            jsonrpc: "2.0",
            id: req.id,
            result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] },
          };
        }

        if (name === "gpt_process") {
          const result = await gptProcess(
            args.sources as string[],
            args.focus as string,
            env.OPENAI_API_KEY,
            model,
            chunkSize,
            maxParallel
          );
          return {
            jsonrpc: "2.0",
            id: req.id,
            result: { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] },
          };
        }

        return {
          jsonrpc: "2.0",
          id: req.id,
          error: { code: -32601, message: `Unknown tool: ${name}` },
        };
      }

      default:
        return {
          jsonrpc: "2.0",
          id: req.id,
          error: { code: -32601, message: `Method not found: ${req.method}` },
        };
    }
  } catch (e) {
    return {
      jsonrpc: "2.0",
      id: req.id,
      error: { code: -32603, message: String(e) },
    };
  }
}

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

async function gptSearch(
  queries: string[],
  focus: string,
  apiKey: string,
  model: string,
  maxParallel: number
): Promise<Array<{ query: string; findings: string; sources_used: string[] }>> {
  const results: Array<{ query: string; findings: string; sources_used: string[] }> = [];

  for (let i = 0; i < queries.length; i += maxParallel) {
    const batch = queries.slice(i, i + maxParallel);
    const batchResults = await Promise.all(
      batch.map(async (query) => {
        try {
          const resp = await fetch("https://api.openai.com/v1/responses", {
            method: "POST",
            headers: {
              Authorization: `Bearer ${apiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              model,
              tools: [{ type: "web_search_preview" }],
              input: `Focus on extracting information relevant to: ${focus}\n\nSearch query: ${query}\n\nReturn a concise TL;DR of the most relevant findings. Include key facts and source URLs.`,
            }),
          });

          if (!resp.ok) throw new Error(`OpenAI ${resp.status}: ${await resp.text()}`);

          const data = (await resp.json()) as {
            output: Array<{
              type: string;
              content?: Array<{
                type: string;
                text?: string;
                annotations?: Array<{ url?: string }>;
              }>;
            }>;
          };

          let findings = "";
          const sources: string[] = [];
          for (const item of data.output ?? []) {
            if (item.type === "message") {
              for (const block of item.content ?? []) {
                if (block.type === "output_text" && block.text) {
                  findings += block.text;
                  for (const ann of block.annotations ?? []) {
                    if (ann.url) sources.push(ann.url);
                  }
                }
              }
            }
          }
          return { query, findings: findings.trim(), sources_used: sources };
        } catch (e) {
          return { query, findings: `ERROR: ${String(e)}`, sources_used: [] };
        }
      })
    );
    results.push(...batchResults);
  }

  return results;
}

async function gptProcess(
  sources: string[],
  focus: string,
  apiKey: string,
  model: string,
  chunkSize: number,
  maxParallel: number
): Promise<Array<{ source: string; summary: string; chunk_count: number }>> {
  const results: Array<{ source: string; summary: string; chunk_count: number }> = [];

  for (let i = 0; i < sources.length; i += maxParallel) {
    const batch = sources.slice(i, i + maxParallel);
    const batchResults = await Promise.all(
      batch.map(async (source) => {
        try {
          let text: string;
          if (source.startsWith("http://") || source.startsWith("https://")) {
            const resp = await fetch(source, { headers: { "User-Agent": "gpt-worker-mcp/1.0" } });
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            const ct = resp.headers.get("content-type") ?? "";
            const raw = await resp.text();
            text = ct.includes("html") ? raw.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim() : raw;
          } else {
            text = source;
          }

          const chunkChars = chunkSize * 4;
          const chunks: string[] = [];
          for (let j = 0; j < text.length; j += chunkChars) {
            chunks.push(text.slice(j, j + chunkChars));
          }
          if (chunks.length === 0) chunks.push(text);

          const chat = async (messages: Array<{ role: string; content: string }>) => {
            const r = await fetch("https://api.openai.com/v1/chat/completions", {
              method: "POST",
              headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
              body: JSON.stringify({ model, messages, max_completion_tokens: 1024 }),
            });
            if (!r.ok) throw new Error(`OpenAI ${r.status}: ${await r.text()}`);
            const d = (await r.json()) as { choices: Array<{ message: { content: string } }> };
            return d.choices[0].message.content ?? "";
          };

          const chunkSummaries = await Promise.all(
            chunks.map((chunk) =>
              chat([
                {
                  role: "system",
                  content: `You are a precise summarizer. Extract only what is relevant to: ${focus}. Be concise. Omit anything unrelated.`,
                },
                { role: "user", content: chunk },
              ])
            )
          );

          const summary =
            chunkSummaries.length === 1
              ? chunkSummaries[0]
              : await chat([
                  {
                    role: "system",
                    content: `Consolidate these summaries into one coherent summary focused on: ${focus}. Remove repetition. Be concise.`,
                  },
                  { role: "user", content: chunkSummaries.join("\n\n---\n\n") },
                ]);

          return { source, summary, chunk_count: chunks.length };
        } catch (e) {
          return { source, summary: `ERROR: ${String(e)}`, chunk_count: 0 };
        }
      })
    );
    results.push(...batchResults);
  }

  return results;
}
