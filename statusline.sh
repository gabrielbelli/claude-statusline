#!/usr/bin/env bash
# Claude Code status line — lean

# bash's printf parses floats through LC_NUMERIC, so in any locale with a comma
# decimal separator — de, fr, pt_BR, es, it, nl, ru, tr, most of continental
# Europe and Latin America — `printf '%.0f' 31.4` either refuses the argument
# outright (bash 3.2) or parses "31" and stops (bash 5.3). The ⚡ and ◉ segments
# then draw a plausible wrong number rather than losing a segment, which is the
# one failure mode this script is otherwise built to avoid, and each render
# leaks a `printf: invalid number` line to stderr.
#
# LC_ALL has to be *unset* rather than merely overridden: it outranks
# LC_NUMERIC, so setting LC_NUMERIC alone fixes nothing. Its value moves to
# LC_CTYPE first, because that is the one setting this script genuinely wants
# from the user — `${#p}` and `${p:0:n}` in shorten_path count characters, and
# a C LC_CTYPE would elide a multibyte path mid-character.
if [ -n "${LC_ALL:-}" ]; then LC_CTYPE="$LC_ALL"; fi
unset LC_ALL
LC_NUMERIC=C
export LC_NUMERIC LC_CTYPE

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
proj_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
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

# ── Config ─────────────────────────────────────────────────────────────────
# Per-segment display, so the line fits a narrow terminal. One key=value per
# line, `#` comments and blanks ignored — the same format claudio uses, so
# there is one config idiom to learn rather than two.
#
#   default=full|short|off     fallback for any segment not named
#   <segment>=full|short|off
#   dir_max=<n>                elide the path when longer than n characters
#
# Segments: account dir model git claudio telemetry pyenv mcp docker context rates
#
# No associative arrays here: macOS still ships bash 3.2 as /bin/bash, and the
# shebang resolves to whichever bash is first on PATH.
# Claude Code reads its config from $CLAUDE_CONFIG_DIR when set, and only falls
# back to $HOME. A claudio account IS a config dir, with its own .claude.json
# holding its own mcpServers — so reading $HOME unconditionally reports another
# account's MCP servers and another account's Docker gateway profile.
CLAUDE_JSON="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"

CONF="${CLAUDE_STATUSLINE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline.conf}"
# shellcheck disable=SC2034  # read via eval in the resolve loop below
cfg_default=full
cfg_dir_max=0
cfg_account=""; cfg_dir=""; cfg_model=""; cfg_git=""; cfg_claudio=""
cfg_telemetry=""; cfg_pyenv=""; cfg_mcp=""; cfg_docker=""; cfg_context=""; cfg_rates=""
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    # Trim without forking: this runs on every render.
    key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    if [ "$key" = "dir_max" ]; then
      case "$val" in ''|*[!0-9]*) : ;; *) cfg_dir_max="$val" ;; esac
      continue
    fi
    # Unknown values are ignored rather than fatal: a typo should cost you one
    # segment's styling, not your whole status line.
    case "$val" in full|short|off) ;; *) continue ;; esac
    case "$key" in
      default)   cfg_default="$val" ;;
      account)   cfg_account="$val" ;;
      dir)       cfg_dir="$val" ;;
      model)     cfg_model="$val" ;;
      git)       cfg_git="$val" ;;
      claudio)   cfg_claudio="$val" ;;
      telemetry) cfg_telemetry="$val" ;;
      pyenv)     cfg_pyenv="$val" ;;
      mcp)       cfg_mcp="$val" ;;
      docker)    cfg_docker="$val" ;;
      context)   cfg_context="$val" ;;
      rates)     cfg_rates="$val" ;;
    esac
  done < "$CONF"
fi
# Resolve each to a plain variable now, so the segments below are simple string
# tests rather than function calls — eleven subshells per render would be worse
# than anything this config saves.
for _s in account dir model git claudio telemetry pyenv mcp docker context rates; do
  eval "[ -n \"\$cfg_$_s\" ] || cfg_$_s=\$cfg_default"
done

shorten_path() {
  # Elide the middle of a path that overruns $2, keeping the first component
  # and the last: those are what tell ~/work/acme/api from ~/play/acme/api.
  # If the final component alone still overruns, cut ITS middle for the same
  # reason — the two ends of a name carry the identity, the middle rarely does.
  local p="$1" max="$2" first last mid keep h t
  case "$max" in ''|*[!0-9]*) printf '%s' "$p"; return ;; esac
  [ "$max" -le 0 ] && { printf '%s' "$p"; return; }
  [ "${#p}" -le "$max" ] && { printf '%s' "$p"; return; }

  last="${p##*/}"; first="${p%%/*}"
  [ -z "$first" ] && first="/"
  if [ "$first" != "$p" ] && [ "$last" != "$p" ]; then
    mid="${first}/…/${last}"
    [ "${#mid}" -le "$max" ] && { printf '%s' "$mid"; return; }
  fi

  keep=$(( max - 1 )); [ "$keep" -lt 4 ] && keep=4
  h=$(( (keep + 1) / 2 )); t=$(( keep / 2 ))
  printf '%s…%s' "${last:0:h}" "${last: -t}"
}

# ── Model + effort ─────────────────────────────────────────────────────────
model_part=""
if [ "$cfg_model" != off ] && [ -n "$model_name" ]; then
  model_part="$(b 141)${model_name}$(r)"
  if [ "$cfg_model" = full ] && [ -n "$effort" ] && [ "$effort" != "null" ]; then
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
[ "$cfg_dir" = short ] && dir="${dir##*/}"
[ "$cfg_dir" = off ] && dir=""
[ -n "$dir" ] && dir=$(shorten_path "$dir" "$cfg_dir_max")

# ── Git ────────────────────────────────────────────────────────────────────
git_part=""
if [ "$cfg_git" != off ] && [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  staged=$(git -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  unstaged=$(git -C "$cwd" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  stashes=$(git -C "$cwd" stash list 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(git -C "$cwd" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  behind=$(git -C "$cwd" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
  git_user=$(git -C "$cwd" config user.email 2>/dev/null)
  # short keeps WHICH identity you are committing as, just without the domain —
  # the local part is what differs between your accounts, the domain rarely is.
  [ "$cfg_git" = short ] && git_user="${git_user%%@*}"

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
if [ "$cfg_claudio" != off ]; then
  marker=""
  [ -n "$cwd" ] && [ -f "${cwd}/.claudio" ] && marker="${cwd}/.claudio"
  [ -z "$marker" ] && [ -n "$proj_dir" ] && [ -f "${proj_dir}/.claudio" ] && marker="${proj_dir}/.claudio"
  if [ -n "$marker" ]; then
    p=$(head -1 "$marker" 2>/dev/null)
    [ -n "$p" ] && claudio="$(c 183)🎭 ${p}$(r)"
  fi
fi

# ── Account ────────────────────────────────────────────────────────────────
# Which claude.ai login is this session actually on? `claudio run` exports
# CLAUDE_CONFIG_DIR to pick an isolated account, and the status line inherits
# it because Claude Code spawns us as a child. Unset means the default login —
# which is worth flagging in a different colour, because silently working under
# the wrong account is the exact failure the whole accounts feature prevents.
# The name is the config dir's basename; the email confirms *which* login it is
# and comes from that dir's own .claude.json (macOS keeps the secret in the
# Keychain, so only the marker lives on disk).
acct=""
if [ "$cfg_account" = off ]; then
  :
elif [ -n "$CLAUDE_CONFIG_DIR" ]; then
  aname=$(basename "$CLAUDE_CONFIG_DIR")
  if [ "$cfg_account" = short ]; then acct="$(c 117)👤$(r)"; else acct="$(c 117)👤 ${aname}$(r)"; fi
else
  amail=$(jq -r '.oauthAccount.emailAddress // empty' "$CLAUDE_JSON" 2>/dev/null)
  # Local part only: the domain is the same for every account and just eats width.
  [ -n "$amail" ] && amail="${amail%%@*}"
  # The globe carries "no claudio account" on its own, so the word is dead
  # weight. Amber regardless: this is the state worth noticing.
  acct="$(c 214)🌐$(r)"
  if [ "$cfg_account" = full ] && [ -n "$amail" ]; then acct="${acct}$(c 240)·$(r)$(c 245)${amail}$(r)"; fi
fi

# ── Telemetry ──────────────────────────────────────────────────────────────
# Shown only when on. Telemetry is opt-in and off by default, so a permanent
# "off" indicator would be noise on every render for every user.
otel=""
if [ "$cfg_telemetry" != off ] && [ "$CLAUDE_CODE_ENABLE_TELEMETRY" = "1" ]; then
  dest="${OTEL_EXPORTER_OTLP_ENDPOINT#*://}"   # strip scheme; host:port is the useful part
  otel="$(c 76)📡$(r)"
  if [ "$cfg_telemetry" = full ] && [ -n "$dest" ]; then otel="${otel} $(c 245)${dest}$(r)"; fi
fi

# ── Python env ─────────────────────────────────────────────────────────────
pyenv=""
if [ "$cfg_pyenv" = off ]; then
  :
elif [ -n "$VIRTUAL_ENV" ]; then
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
docker_part=""
docker_in_use=0
if command -v docker >/dev/null 2>&1 && [ -f "$CLAUDE_JSON" ]; then
  key="${proj_dir:-$cwd}"
  # local scope (project entry inside ~/.claude.json)
  dargs=$(jq -c --arg k "$key" '.projects[$k].mcpServers.MCP_DOCKER.args // empty' "$CLAUDE_JSON" 2>/dev/null)
  # project scope (shared .mcp.json)
  if [ -z "$dargs" ] && [ -n "$proj_dir" ] && [ -f "${proj_dir}/.mcp.json" ]; then
    dargs=$(jq -c '.mcpServers.MCP_DOCKER.args // empty' "${proj_dir}/.mcp.json" 2>/dev/null)
  fi
  # user scope (top-level)
  if [ -z "$dargs" ]; then
    dargs=$(jq -c '.mcpServers.MCP_DOCKER.args // empty' "$CLAUDE_JSON" 2>/dev/null)
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
    if [ -n "$dcount" ] && [ "$cfg_docker" != off ]; then
      if [ "$cfg_docker" = full ]; then docker_part="$(c 39)🐳 ${dprofile}·${dcount}$(r)"
      else docker_part="$(c 39)🐳${dcount}$(r)"; fi
    fi
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
if [ -f "$CLAUDE_JSON" ]; then
  glob_mcp=$(jq "[.mcpServers // {} | keys[] | ${drop}] | length" "$CLAUDE_JSON" 2>/dev/null || echo 0)
fi
if [ "$cfg_mcp" != off ] && { [ "$proj_mcp" -gt 0 ] || [ "$glob_mcp" -gt 0 ]; }; then
  if [ "$cfg_mcp" = full ]; then
    mcp_part="$(c 208)🔌$(r) $(c 76)${proj_mcp}$(dim)p$(r) $(c 245)${glob_mcp}$(dim)g$(r)"
  else
    # Total, not project-only: the project count is the same everywhere you
    # work, while the global count changes with the account. Showing only the
    # invariant half made three different accounts render identically.
    mcp_part="$(c 208)🔌$(r)$(c 76)$(( proj_mcp + glob_mcp ))$(r)"
  fi
fi

# ── Context ────────────────────────────────────────────────────────────────
ctx=""
if [ "$cfg_context" != off ] && [ -n "$used_pct" ]; then
  pct=$(printf '%.0f' "$used_pct")
  ctx="$(c $(rate_col "$pct"))${pct}%$(r)"
fi

# ── Rate limits ────────────────────────────────────────────────────────────
rates=""
if [ "$cfg_rates" = off ]; then
  :
elif [ -n "$rl_5h" ] && [ "$rl_5h" != "null" ]; then
  p5=$(printf '%.0f' "$rl_5h")
  t5=$(countdown "$rl_5h_reset")
  rates="$(c $(rate_col "$p5"))${p5}%$(r)"
  if [ "$cfg_rates" = full ] && [ -n "$t5" ]; then rates="${rates} $(c 240)↻${t5}$(r)"; fi
fi
if [ "$cfg_rates" != off ] && [ -n "$rl_7d" ] && [ "$rl_7d" != "null" ]; then
  p7=$(printf '%.0f' "$rl_7d")
  t7=$(countdown "$rl_7d_reset")
  if [ -n "$rates" ]; then
    if [ "$cfg_rates" = full ]; then rates="${rates} $(c 240)/$(r) "; else rates="${rates}$(c 240)/$(r)"; fi
  fi
  rates="${rates}$(c $(rate_col "$p7"))${p7}%$(r)"
  if [ "$cfg_rates" = full ] && [ -n "$t7" ]; then rates="${rates} $(c 240)↻${t7}$(r)"; fi
fi

# ── Build line ─────────────────────────────────────────────────────────────
sep="  $(c 240)│$(r)  "
out=""
# Join rather than append: any segment can be switched off, and appending a
# separator to an empty string leaves a stray divider with nothing beside it.
add() {
  [ -z "$1" ] && return 0
  if [ -z "$out" ]; then out="$1"; else out="${out}${sep}$1"; fi
  return 0
}

# Account leads: which login is being billed is the highest-stakes fact here,
# and the one you least want to discover after the fact.
add "$acct"
[ -n "$dir" ] && add "$(b 75)${dir}$(r)"
add "$model_part"
if [ -n "$git_part" ]; then
  # The committing identity rides with the branch rather than as its own
  # segment: it qualifies the branch, and a divider would overstate it.
  [ -n "$git_user" ] && git_part="${git_part} $(c 245)${git_user}$(r)"
  add "$git_part"
fi
add "$claudio"
add "$otel"
add "$pyenv"
add "$mcp_part"
add "$docker_part"
if [ -n "$ctx" ]; then
  if [ "$cfg_context" = full ]; then add "$(c 240)◉$(r) ${ctx}"; else add "$ctx"; fi
fi
[ -n "$rates" ] && add "$(c 240)⚡$(r)${rates}"

printf '%b' "$out"
