# claude-statusline

Custom status line for [Claude Code](https://code.claude.com). A single bash script that reads the status line JSON from stdin and prints one ANSI-coloured line.

## Segments (left to right)

| Segment | Source | Notes |
|---|---|---|
| Directory | `.workspace.current_dir` | `~`-abbreviated |
| Model · effort | `.model.display_name`, `.effort.level` | effort colour-coded: green (low) → red (xhigh/max) |
| Git | `git` CLI | branch, ahead/behind, staged/unstaged/untracked, stashes, user email |
| Claudio | `.claudio` file in cwd | persona indicator, if present |
| Python env | `$VIRTUAL_ENV` / conda | skipped for `base` |
| Context | `.context_window.used_percentage` | `◉` |
| Rate limits | `.rate_limits.five_hour` / `.seven_day` | `⚡` used % + `↻` reset countdown |

> **Note on per-model limits:** the status line JSON only exposes account-wide 5-hour and 7-day usage — there is no Fable-specific (per-model) breakdown. The `⚡` segment is the closest available proxy.

## Install

Point `~/.claude/settings.json` at the script:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /Users/belli/Projects/claude-statusline/statusline.sh"
  }
}
```

## Test

```bash
echo '{"workspace":{"current_dir":"/Users/belli/Projects"},"model":{"display_name":"Fable 5"},"effort":{"level":"high"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":31},"seven_day":{"used_percentage":66}}}' | bash statusline.sh
```

## Dependencies

- `jq`
- `git` (optional — segment skipped outside repos)
