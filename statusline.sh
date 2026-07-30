#!/usr/bin/env bash
# Claude Code status line — lean

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
rl_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

c() { printf '\033[38;5;%dm' "$1"; }
b() { printf '\033[1;38;5;%dm' "$1"; }
r() { printf '\033[0m'; }
dim() { printf '\033[2m'; }

countdown() {
  local reset_raw="$1"
  [ -z "$reset_raw" ] || [ "$reset_raw" = "null" ] && return
  local now=$(date +%s)
  local ts=$(printf '%.0f' "$reset_raw")
  [ "$ts" -le "$now" ] 2>/dev/null && return
  local d=$(( ts - now ))
  if [ "$d" -ge 86400 ]; then echo "$(( d / 86400 ))d$(( (d % 86400) / 3600 ))h"
  elif [ "$d" -ge 3600 ]; then echo "$(( d / 3600 ))h$(( (d % 3600) / 60 ))m"
  else echo "$(( d / 60 ))m"; fi
}

rate_col() {
  local p=$(printf '%.0f' "$1")
  if [ "$p" -lt 50 ]; then echo 76; elif [ "$p" -lt 80 ]; then echo 214; else echo 196; fi
}

# ── Model + effort ─────────────────────────────────────────────────────────
model_part=""
if [ -n "$model_name" ]; then
  model_part="$(b 141)${model_name}$(r)"
  if [ -n "$effort" ] && [ "$effort" != "null" ]; then
    case "$effort" in
      low) ec=76 ;;
      medium) ec=178 ;;
      high) ec=214 ;;
      xhigh|max) ec=196 ;;
      *) ec=245 ;;
    esac
    model_part="${model_part} $(c 240)·$(r) $(c "$ec")${effort}$(r)"
  fi
fi

# ── Directory ──────────────────────────────────────────────────────────────
home_escaped=$(printf '%s' "$HOME" | sed 's/[\/&]/\\&/g')
dir=$(echo "$cwd" | sed "s/^${home_escaped}/~/")
[ -z "$dir" ] && dir="?"

# ── Git ────────────────────────────────────────────────────────────────────
git_part=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  staged=$(git -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  unstaged=$(git -C "$cwd" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  stashes=$(git -C "$cwd" stash list 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(git -C "$cwd" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  behind=$(git -C "$cwd" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
  git_user=$(git -C "$cwd" config user.email 2>/dev/null)

  f=""
  [ "$behind" -gt 0 ] 2>/dev/null  && f="${f} $(c 76)⇣${behind}"
  [ "$ahead" -gt 0 ] 2>/dev/null   && f="${f} $(c 76)⇡${ahead}"
  [ "$stashes" -gt 0 ] 2>/dev/null && f="${f} $(c 76)*${stashes}"
  [ "$staged" -gt 0 ] 2>/dev/null  && f="${f} $(c 178)+${staged}"
  [ "$unstaged" -gt 0 ] 2>/dev/null && f="${f} $(c 178)!${unstaged}"
  [ "$untracked" -gt 0 ] 2>/dev/null && f="${f} $(c 76)?${untracked}"

  git_part="$(b 76)${branch}$(r)${f}$(r)"
fi

# ── Claudio ────────────────────────────────────────────────────────────────
claudio=""
if [ -n "$cwd" ] && [ -f "${cwd}/.claudio" ]; then
  p=$(head -1 "${cwd}/.claudio" 2>/dev/null)
  [ -n "$p" ] && claudio="$(c 183)🎭 ${p}$(r)"
fi

# ── Python env ─────────────────────────────────────────────────────────────
pyenv=""
if [ -n "$VIRTUAL_ENV" ]; then
  vname=$(basename "$VIRTUAL_ENV")
  case "$vname" in venv|.venv|env|.env) vname=$(basename "$(dirname "$VIRTUAL_ENV")") ;; esac
  pyenv="$(c 39)🐍 ${vname}$(r)"
elif [ -n "$CONDA_DEFAULT_ENV" ] && [ "$CONDA_DEFAULT_ENV" != "base" ]; then
  pyenv="$(c 39)🐍 ${CONDA_DEFAULT_ENV}$(r)"
fi

# ── Docker MCP Toolkit profile ─────────────────────────────────────────────
# The Docker gateway shows up in Claude's config as a SINGLE server
# (MCP_DOCKER) that fronts N toolkit servers. This segment surfaces the active
# profile and how many servers it holds; the plug segment below then drops the
# gateway from its own tally so the same thing isn't counted twice.
# Active profile = --profile arg of the gateway command (absent = "default").
# MCP_DOCKER can be registered at three scopes and Claude resolves them
# local > project > user, so we must look up the args in that same order:
#   local   → ~/.claude.json .projects[<project_dir>].mcpServers.MCP_DOCKER
#   project → <project_dir>/.mcp.json .mcpServers.MCP_DOCKER
#   user    → ~/.claude.json .mcpServers.MCP_DOCKER  (top level)
# Reading only the top level (user scope) misses a project-local override.
# Server count via `docker mcp`, cached 60s — the status line re-renders
# constantly and must not shell out to docker each time.
proj_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
docker_part=""
docker_in_use=0
if command -v docker >/dev/null 2>&1 && [ -f "$HOME/.claude.json" ]; then
  key="${proj_dir:-$cwd}"
  # local scope (project entry inside ~/.claude.json)
  dargs=$(jq -c --arg k "$key" '.projects[$k].mcpServers.MCP_DOCKER.args // empty' "$HOME/.claude.json" 2>/dev/null)
  # project scope (shared .mcp.json)
  if [ -z "$dargs" ] && [ -n "$proj_dir" ] && [ -f "${proj_dir}/.mcp.json" ]; then
    dargs=$(jq -c '.mcpServers.MCP_DOCKER.args // empty' "${proj_dir}/.mcp.json" 2>/dev/null)
  fi
  # user scope (top-level)
  if [ -z "$dargs" ]; then
    dargs=$(jq -c '.mcpServers.MCP_DOCKER.args // empty' "$HOME/.claude.json" 2>/dev/null)
  fi
fi
if [ -n "$dargs" ]; then
  docker_in_use=1
  dprofile=$(printf '%s' "$dargs" | jq -r 'index("--profile") as $i
                    | if $i then .[$i+1] else "default" end' 2>/dev/null)
  if [ -n "$dprofile" ] && [ "$dprofile" != "null" ]; then
    dcache="${TMPDIR:-/tmp}/claude-statusline-dockermcp-${dprofile}"
    now=$(date +%s)
    mtime=$(stat -f %m "$dcache" 2>/dev/null || stat -c %Y "$dcache" 2>/dev/null || echo 0)
    if [ $(( now - mtime )) -gt 60 ]; then
      docker mcp profile server ls 2>/dev/null \
        | awk -v p="$dprofile" '$1 == p' | wc -l | tr -d ' ' > "$dcache" 2>/dev/null
    fi
    dcount=$(cat "$dcache" 2>/dev/null)
    [ -n "$dcount" ] && docker_part="$(c 39)🐳 ${dprofile}·${dcount}$(r)"
  fi
fi

# ── MCP servers (plug) ─────────────────────────────────────────────────────
# Split project (shared .mcp.json) vs global (~/.claude.json). The Docker
# gateway is excluded whenever the 🐳 segment is showing it, so it is neither
# double-counted nor silently dropped — if docker isn't in use, it still counts.
mcp_part=""
if [ "$docker_in_use" -eq 1 ]; then drop='select(. != "MCP_DOCKER")'; else drop='.'; fi

proj_mcp=0
if [ -n "$proj_dir" ] && [ -f "${proj_dir}/.mcp.json" ]; then
  proj_mcp=$(jq "[.mcpServers // {} | keys[] | ${drop}] | length" "${proj_dir}/.mcp.json" 2>/dev/null || echo 0)
fi
glob_mcp=0
if [ -f "$HOME/.claude.json" ]; then
  glob_mcp=$(jq "[.mcpServers // {} | keys[] | ${drop}] | length" "$HOME/.claude.json" 2>/dev/null || echo 0)
fi
if [ "$proj_mcp" -gt 0 ] || [ "$glob_mcp" -gt 0 ]; then
  mcp_part="$(c 208)🔌$(r) $(c 76)${proj_mcp}$(dim)p$(r) $(c 245)${glob_mcp}$(dim)g$(r)"
fi

# ── Context ────────────────────────────────────────────────────────────────
ctx=""
if [ -n "$used_pct" ]; then
  pct=$(printf '%.0f' "$used_pct")
  ctx="$(c $(rate_col "$pct"))${pct}%$(r)"
fi

# ── Rate limits ────────────────────────────────────────────────────────────
rates=""
if [ -n "$rl_5h" ] && [ "$rl_5h" != "null" ]; then
  p5=$(printf '%.0f' "$rl_5h")
  t5=$(countdown "$rl_5h_reset")
  rates="$(c $(rate_col "$p5"))${p5}%$(r)"
  [ -n "$t5" ] && rates="${rates} $(c 240)↻${t5}$(r)"
fi
if [ -n "$rl_7d" ] && [ "$rl_7d" != "null" ]; then
  p7=$(printf '%.0f' "$rl_7d")
  t7=$(countdown "$rl_7d_reset")
  [ -n "$rates" ] && rates="${rates} $(c 240)/$(r) "
  rates="${rates}$(c $(rate_col "$p7"))${p7}%$(r)"
  [ -n "$t7" ] && rates="${rates} $(c 240)↻${t7}$(r)"
fi

# ── Build line ─────────────────────────────────────────────────────────────
sep="  $(c 240)│$(r)  "
out="$(b 75)${dir}$(r)"
[ -n "$model_part" ] && out="${out}${sep}${model_part}"
[ -n "$git_part" ] && out="${out}${sep}${git_part}"
[ -n "$git_user" ] && out="${out} $(c 245)${git_user}$(r)"
[ -n "$claudio" ]  && out="${out}${sep}${claudio}"
[ -n "$pyenv" ]    && out="${out}${sep}${pyenv}"
[ -n "$mcp_part" ] && out="${out}${sep}${mcp_part}"
[ -n "$docker_part" ] && out="${out}${sep}${docker_part}"
[ -n "$ctx" ]      && out="${out}${sep}$(c 240)◉$(r) ${ctx}"
[ -n "$rates" ]    && out="${out}${sep}$(c 240)⚡$(r)${rates}"

printf '%b' "$out"
