# Claude Skills

AI tooling integrations for the AGS script library. These are MCP servers and utilities that extend Claude with additional capabilities, allowing it to delegate tasks to external AI services and tools.

## Available skills

| Skill | Description |
|-------|-------------|
| [gpt-worker](gpt-worker/README.md) | Routes Claude's research and document processing tasks to GPT-5.4 as a parallel worker pool via MCP |

## What is MCP?

MCP (Model Context Protocol) is the standard way to give Claude new tools. Each skill in this directory is an MCP server that Claude Code connects to locally over stdio. Claude calls the tools exposed by these servers as part of its normal reasoning — no manual invocation needed.

## Adding a skill to Claude Code

Each skill's `README.md` contains the exact JSON snippet to add to `~/.claude.json`. General pattern:

```json
{
  "mcpServers": {
    "skill-name": {
      "command": "python",
      "args": ["<SCRIPT_FOLDER>/Claude skills/skill-name/server.py"]
    }
  }
}
```

After editing `~/.claude.json`, restart Claude Code and run `/mcp` to confirm the tools loaded.
