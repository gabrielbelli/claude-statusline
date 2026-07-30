# claude-statusline

Custom status line for [Claude Code](https://code.claude.com). A single bash script that reads the status line JSON from stdin and prints one ANSI-coloured line.

```
~/Projects  │  Fable 5 · high  │  main ⇡1 !2  │  🔌 5p 0g  │  🐳 default·4  │  ◉ 42%  │  ⚡31% ↻2h0m / 66% ↻2d7h
```

## Segments (left to right)

| Segment | Source | Notes |
|---|---|---|
| Directory | `.workspace.current_dir` | `~`-abbreviated |
| Model · effort | `.model.display_name`, `.effort.level` | effort colour-coded: green (low) → red (xhigh/max) |
| Git | `git` CLI | branch, ahead/behind, staged/unstaged/untracked, stashes, user email |
| Claudio | `.claudio` file in cwd | persona indicator, if present |
| Python env | `$VIRTUAL_ENV` / conda | skipped for `base` |
| MCP servers | project `.mcp.json` + `~/.claude.json` | `🔌 Np Mg` — project vs global count; the Docker gateway is excluded when the `🐳` segment shows it |
| Docker MCP Toolkit | `docker mcp` CLI | `🐳` active gateway profile · server count, cached 60 s |
| Context | `.context_window.used_percentage` | `◉` |
| Rate limits | `.rate_limits.five_hour` / `.seven_day` | `⚡` used % + `↻` reset countdown |

> **Note on per-model limits:** the status line JSON only exposes account-wide 5-hour and 7-day usage — there is no per-model breakdown. The `⚡` segment is the closest available proxy.

## Install

Clone the repo, then point `statusLine` in `~/.claude/settings.json` at the script:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/claude-statusline/statusline.sh"
  }
}
```

## Test

```bash
echo '{"workspace":{"current_dir":"'"$HOME"'/Projects"},"model":{"display_name":"Fable 5"},"effort":{"level":"high"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":31},"seven_day":{"used_percentage":66}}}' | bash statusline.sh
```

## Graceful degradation

Every segment is optional and self-guarding: if a tool, file, or data field is
missing (no `docker`, no `.mcp.json`, no git repo, no rate-limit data, …) that
segment simply doesn't render — the status line never errors or shows a broken
placeholder. Only `jq` and the directory/model segments are effectively always
on; everything else appears only when it applies to your setup.

## Dependencies

- `jq`
- `git` (optional — segment skipped outside repos)
- `docker` with the MCP Toolkit CLI plugin (optional — segment skipped if absent)

## Licence

[BSD 2-Clause](LICENSE)
