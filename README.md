# claude-statusline

Custom status line for [Claude Code](https://code.claude.com). A single bash script that reads the status line JSON from stdin and prints one ANSI-coloured line.

```bash
brew install gabrielbelli/tap/claude-statusline
```

```
👤 work  │  ~/Projects  │  Fable 5 · high  │  main ⇡1 !2  │  🎭 soc  │  📡 localhost:4317  │  🔌 5p 0g  │  🐳 default·4  │  ◉ 42%  │  ⚡31% ↻2h0m / 66% ↻2d7h
```

## Segments (left to right)

| Segment | Source | Notes |
|---|---|---|
| Account | `$CLAUDE_CONFIG_DIR`, else `~/.claude.json` | `👤 <name>` the claudio account you're running as. **Amber `🌐·<user>`** when no account is set, because working under the default login unawares is the failure this is here to catch |
| Directory | `.workspace.current_dir` | `~`-abbreviated |
| Model · effort | `.model.display_name`, `.effort.level` | effort colour-coded: green (low) → red (xhigh/max) |
| Git | `git` CLI | branch, ahead/behind, staged/unstaged/untracked, stashes, user email |
| Claudio | `.claudio` file in cwd | active claudio profile name, if present |
| Telemetry | `$CLAUDE_CODE_ENABLE_TELEMETRY` | `📡` + endpoint host. Hidden entirely when off, which is the default |
| Python env | `$VIRTUAL_ENV` / conda | skipped for `base` |
| MCP servers | project `.mcp.json` + `~/.claude.json` | `🔌 Np Mg` — project vs global count; the Docker gateway is excluded when the `🐳` segment shows it |
| Docker MCP Toolkit | `docker mcp` CLI | `🐳` active gateway profile · server count, cached 60 s |
| Context | `.context_window.used_percentage` | `◉` |
| Rate limits | `.rate_limits.five_hour` / `.seven_day` | `⚡` used % + `↻` reset countdown |

> **Note on per-model limits:** the status line JSON only exposes account-wide 5-hour and 7-day usage — there is no per-model breakdown. The `⚡` segment is the closest available proxy.

## Better with claudio

Three of the segments — `🎭` profile, `👤` account, `📡` telemetry — are reporting on [**claudio**](https://github.com/gabrielbelli/claudio), a profile and account manager for Claude Code. Without it they simply don't render, and the rest of the line works exactly as before.

With it, the line answers the two questions that are otherwise invisible until it's too late:

- **Which login is this session billing?** `claudio` gives each account its own isolated `CLAUDE_CONFIG_DIR`, and the status line names it. Amber `🌐` means you're on your default login rather than a managed account — which is exactly when you'd want to know.
- **Which project configuration is live?** A claudio profile bundles MCP servers, permissions, hooks, skills and instructions, symlinked into the directory. `🎭` names the active one.

```bash
claudio account new work        # isolated login
claudio use soc                 # link a profile here
claudio run --account work      # launch with both, tagged
```

Because an account is a separate config dir, the `🔌` and `🐳` counts follow it too — running under `work` reports `work`'s MCP servers, not your default account's.

## Configuration

Optional. With no config file the line renders exactly as above.

```bash
cp "$(brew --prefix)/opt/claude-statusline/share/claude-statusline/claude-statusline.conf.example" \
   ~/.config/claude-statusline.conf
```

(or `cp claude-statusline.conf.example ~/.config/` from a clone)

Every segment takes `full`, `short` or `off`, and `default=` sets the fallback for anything you don't name — so one line fits a narrow terminal:

```ini
default=short        # everything compact
account=full         # except this — worth its width
git=off
dir_max=24           # elide the path beyond 24 characters
```

| Segment | `full` | `short` |
|---|---|---|
| `account` | `👤 blue-agent` / `🌐·you` | `👤` / `🌐` |
| `dir` | `~/Projects/claudio` | `claudio` |
| `model` | `Opus 5 · high` | `Opus 5` |
| `git` | `main !2 you@example.com` | `main !2 you` |
| `telemetry` | `📡 localhost:4317` | `📡` |
| `mcp` | `🔌 3p 0g` | `🔌3` — total, project + global |
| `docker` | `🐳 default·2` | `🐳2` |
| `context` | `◉ 42%` | `42%` |
| `rates` | `31% ↻2h0m / 66% ↻2d7h` | `31%/66%` |

`claudio` and `pyenv` have nothing to drop, so `short` matches `full`; both still honour `off`.

**`dir_max`** elides the middle of an over-long path, keeping the first and last components — those are what distinguish `~/work/acme/api` from `~/play/acme/api`:

```
~/Projects/deeply/nested/customer-alpha/services/api-gateway
~/…/api-gateway        dir_max=30
api-ga…teway           dir_max=12   — the final component alone overran, so its middle went
```

Override the location with `$CLAUDE_STATUSLINE_CONF`. Unknown keys and values are skipped rather than fatal: a typo costs you one segment's styling, not the whole line.

## Install

```bash
brew install gabrielbelli/tap/claude-statusline
```

Then point Claude Code at it in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "claude-statusline"
  }
}
```

`brew upgrade` to update, `brew uninstall claude-statusline` to remove. Homebrew pulls in `jq` for you.

<details>
<summary>Without Homebrew</summary>

```bash
git clone https://github.com/gabrielbelli/claude-statusline
```

Then give the full path, remembering the interpreter:

```json
"command": "bash /path/to/claude-statusline/statusline.sh"
```

You'll need `jq` yourself. Update with `git pull`.

> Worth avoiding an absolute path where you can. It breaks the moment the clone moves or is renamed, and it fails by the status line silently disappearing rather than by an error you can read. A command on `PATH` doesn't have that problem.

</details>

## Test

```bash
echo '{"workspace":{"current_dir":"'"$HOME"'/Projects"},"model":{"display_name":"Fable 5"},"effort":{"level":"high"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":31},"seven_day":{"used_percentage":66}}}' | claude-statusline
```

From a clone, `bash statusline.sh` instead.

## Graceful degradation

Every segment is optional and self-guarding: if a tool, file, or data field is
missing (no `docker`, no `.mcp.json`, no git repo, no rate-limit data, …) that
segment simply doesn't render — the status line never errors or shows a broken
placeholder. Only `jq` and the directory/model segments are effectively always
on; everything else appears only when it applies to your setup.

## Dependencies

- `jq` — installed for you by Homebrew
- `git` (optional — segment skipped outside repos)
- `docker` with the MCP Toolkit CLI plugin (optional — segment skipped if absent)

## Licence

[BSD 2-Clause](LICENSE)
