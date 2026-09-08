#!/usr/bin/env bash
# ~/.claude/statusline.sh — Claude Code session status line (aesthetic edition)
#
# 三行輸出：
#   第一行：◆ 模型 │ 漸層進度條 百分比 │ 費用 │ 時間 │ 速率限制
#   第二行：⎇分支* │ +增/-減 │ 目錄
#   第三行：❯ 提示符（顏色跟上下文用量連動）
#
# 環境變數：
#   CLAUDE_STATUSLINE_ASCII=1     退回純 ASCII
#   CLAUDE_STATUSLINE_NERDFONT=1  啟用 Nerd Font 圖示
#   CLAUDE_STATUSLINE_POWERLINE=1 啟用 Powerline 分隔符（預設跟隨 NERDFONT）
#   COLORTERM=truecolor|24bit     系統自動設定，啟用真彩色漸層

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# 環境偵測
# ═══════════════════════════════════════════════════════════════

USE_ASCII="${CLAUDE_STATUSLINE_ASCII:-0}"
USE_NERDFONT="${CLAUDE_STATUSLINE_NERDFONT:-0}"
USE_POWERLINE="${CLAUDE_STATUSLINE_POWERLINE:-$USE_NERDFONT}"
USE_TRUECOLOR=0
if [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]]; then
  USE_TRUECOLOR=1
fi

# ═══════════════════════════════════════════════════════════════
# 色彩與符號
# ═══════════════════════════════════════════════════════════════

CSI=$'\033['
RST=$'\033[0m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
GRAY=$'\033[90m'
DIM=$'\033[2m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
# Anthropic 品牌紫 (#7266EA)
if (( USE_TRUECOLOR )); then
  PURPLE=$'\033[38;2;114;102;234m'
else
  PURPLE=$'\033[35m'
fi

# 符號集
if [[ "$USE_ASCII" == "1" ]]; then
  S_BRAND="<>"
  S_BRANCH=">"
  S_WARN="!"
  S_PROMPT=">"
  S_TIME=""
  S_COST=""
  S_RESET="@"
  SEP="   |   "
elif [[ "$USE_NERDFONT" == "1" ]]; then
  S_BRAND="◆"
  S_BRANCH=" "
  S_WARN=" 󰀦"
  S_PROMPT="❯"
  S_TIME="󰔟 "
  S_COST=""
  S_RESET=" "
  if [[ "$USE_POWERLINE" == "1" ]]; then
    SEP="  "
  else
    SEP="   ·   "
  fi
else
  S_BRAND="◆"
  S_WARN=" ⚠"
  S_PROMPT="❯"
  S_TIME=""
  S_COST=""
  S_RESET="↻"
  if [[ "$USE_POWERLINE" == "1" ]]; then
    # U+E0A0 is a Powerline glyph, so it is available whenever Powerline
    # separators are. It is monospace, so it occupies exactly one cell.
    S_BRANCH=" "
    SEP="  "
  else
    # U+2387 is absent from common monospace fonts (Hack, Noto Sans Mono,
    # DejaVu Sans Mono), so fontconfig falls back to a PROPORTIONAL face such
    # as DejaVu Sans. Its East_Asian_Width is Neutral, so the terminal reserves
    # a single cell, but the proportional glyph is drawn wider than that and
    # bleeds into the next cell -- which held the first letter of the branch
    # name, because this was the only tier without a trailing space. The space
    # absorbs the overflow.
    S_BRANCH="⎇ "
    SEP="   ·   "
  fi
fi

# Strip C0 control characters and DEL from values that reach the terminal.
# A directory name may legally contain a raw ESC, which would otherwise be
# emitted verbatim and run as a terminal control sequence. Range stops at
# \x7f on purpose: 0x80-0x9f are UTF-8 continuation bytes, not C1 controls.
sanitize() {
  local v="${!1}"
  printf -v "$1" '%s' "${v//[$'\x01'-$'\x1f'$'\x7f']/}"
}

# ═══════════════════════════════════════════════════════════════
# 降級輸出
# ═══════════════════════════════════════════════════════════════

fallback_prompt() {
  printf '%s' "${GRAY}${1:-─}${RST}"
  exit 0
}

# An unexpected failure must never leave the status line blank, because empty
# output makes Claude Code render nothing at all.
trap 'fallback_prompt "─"' ERR

# Integer part of a value. Anything non-numeric (null, scientific notation,
# stray command output) becomes 0, so it can never blow up an arithmetic
# context and abort the script under `set -u`.
to_int() { # $1=raw value  $2=target variable name
  local v="${1%%.*}"
  [[ "$v" =~ ^-?[0-9]+$ ]] || v=0
  printf -v "$2" '%s' "$v"
}

command -v jq &>/dev/null || fallback_prompt "─ │ jq not found"

# ═══════════════════════════════════════════════════════════════
# 讀取 JSON（單次 jq）
# ═══════════════════════════════════════════════════════════════

input=$(cat)

parsed=$(echo "$input" | jq -r '
  (.model.display_name // ""),
  (.context_window.used_percentage // 0 | tostring),
  (.cost.total_cost_usd // 0 | tostring),
  (.workspace.current_dir // "." | split("/") | last),
  (.worktree.branch // ""),
  (.rate_limits.five_hour.used_percentage // -1 | tostring),
  (.rate_limits.seven_day.used_percentage // -1 | tostring),
  (.agent.name // ""),
  (.workspace.current_dir // "."),
  (.cost.total_lines_added // 0 | tostring),
  (.cost.total_lines_removed // 0 | tostring),
  (.cost.total_duration_ms // 0 | tostring),
  (.context_window.context_window_size // 0 | tostring),
  (.worktree.name // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.rate_limits.seven_day.resets_at // ""),
  "END"
' 2>/dev/null) || fallback_prompt "─ │ parse error"

{
  IFS= read -r model_name
  IFS= read -r ctx_pct
  IFS= read -r cost
  IFS= read -r dir
  IFS= read -r branch
  IFS= read -r rate5h
  IFS= read -r rate7d
  IFS= read -r agent_name
  IFS= read -r cwd_full
  IFS= read -r lines_add
  IFS= read -r lines_rm
  IFS= read -r duration_ms
  IFS= read -r ctx_size
  IFS= read -r wt_name
  IFS= read -r rate5h_reset
  IFS= read -r rate7d_reset
  IFS= read -r _sentinel
} <<< "$parsed"

for _f in model_name dir branch agent_name cwd_full wt_name rate5h_reset rate7d_reset; do sanitize "$_f"; done

# ═══════════════════════════════════════════════════════════════
# 模型
# ═══════════════════════════════════════════════════════════════

model="${model_name:-─}"

# ═══════════════════════════════════════════════════════════════
# 上下文進度條
# ═══════════════════════════════════════════════════════════════

# ISO 8601 (or a bare epoch) -> epoch seconds; empty string when unparseable.
# GNU date first, then BSD, so one script covers Linux and macOS -- the same
# shape as the stat fallback below. These three always return 0: an ERR trap
# is armed, so a non-zero return would replace the status line with a dash.
reset_epoch() {
  local v="${1:-}" e=""
  if [[ -z "$v" || "$v" == "null" ]]; then printf ''; return 0; fi
  if [[ "$v" =~ ^[0-9]+$ ]]; then printf '%s' "$v"; return 0; fi
  e=$(date -d "$v" +%s 2>/dev/null) || e=""
  if [[ -z "$e" ]]; then
    local t="${v%%.*}"; t="${t%Z}"
    e=$(date -u -jf "%Y-%m-%dT%H:%M:%S" "$t" +%s 2>/dev/null) || e=""
  fi
  printf '%s' "$e"
  return 0
}

# Local clock time (15:42). Absolute, not relative, because renders are
# event-driven: a countdown sits stale on screen while the session is idle.
reset_clock() {
  local e out=""
  e=$(reset_epoch "${1:-}")
  if [[ -n "$e" ]]; then
    out=$(date -d "@$e" +%H:%M 2>/dev/null) || out=""
    if [[ -z "$out" ]]; then out=$(date -r "$e" +%H:%M 2>/dev/null) || out=""; fi
  fi
  printf '%s' "$out"
  return 0
}

# Coarse time remaining (3d / 19h / 45m), for the 7d window where a clock
# time would need a weekday to mean anything. Past resets clamp to 0m.
reset_countdown() {
  local e now diff
  e=$(reset_epoch "${1:-}")
  if [[ -z "$e" ]]; then printf ''; return 0; fi
  now=$(date +%s)
  diff=$(( e - now ))
  if (( diff < 0 )); then diff=0; fi
  if   (( diff >= 86400 )); then printf '%dd' $(( diff / 86400 ))
  elif (( diff >= 3600  )); then printf '%dh' $(( diff / 3600  ))
  else                           printf '%dm' $(( diff / 60    )); fi
  return 0
}

to_int "${ctx_pct:-0}" pct_int
if (( pct_int < 0 )); then pct_int=0; fi
if (( pct_int > 100 )); then pct_int=100; fi

bar_filled=$(( pct_int / 10 ))
if (( bar_filled > 10 )); then bar_filled=10; fi

# 漸層色（真彩色）：綠 → 黃 → 橘 → 紅
GRAD_R=(46 116 186 241 239 236 233 231 211 192)
GRAD_G=(204 195 186 196 161 126 101 76 66 57)
GRAD_B=(113 89 64 15 24 34 44 60 50 43)

bar=""
if [[ "$USE_ASCII" == "1" ]]; then
  # ASCII 模式
  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then bar+="#"; else bar+="-"; fi
  done
elif (( USE_TRUECOLOR )); then
  # 真彩色漸層：每格獨立上色
  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then
      bar+="${CSI}38;2;${GRAD_R[$i]};${GRAD_G[$i]};${GRAD_B[$i]}m█"
    else
      bar+="${CSI}38;2;60;60;60m░"
    fi
  done
  bar+="${RST}"
else
  # ANSI 退回：依整體百分比選色
  if (( pct_int >= 90 )); then bar_color="$RED"
  elif (( pct_int >= 70 )); then bar_color="$YELLOW"
  else bar_color="$GREEN"; fi

  for (( i=0; i<10; i++ )); do
    if (( i < bar_filled )); then bar+="█"; else bar+="░"; fi
  done
  bar="${bar_color}${bar}${RST}"
fi

# 百分比文字顏色（跟進度條整體色一致）
if (( pct_int >= 90 )); then pct_color="$RED"
elif (( pct_int >= 70 )); then pct_color="$YELLOW"
else pct_color="$GREEN"; fi

# 警告符號
ctx_warn=""
if (( pct_int >= 90 )); then ctx_warn="${RED}${S_WARN}${RST}"; fi

# 上下文視窗大小（僅在 model display_name 不包含 context 資訊時才顯示）
to_int "${ctx_size:-0}" ctx_size_int
ctx_label=""
if [[ "$model" != *context* && "$model" != *Context* ]]; then
  if (( ctx_size_int >= 1000000 )); then ctx_label=" ${GRAY}1M${RST}"
  elif (( ctx_size_int >= 200000 )); then ctx_label=" ${GRAY}200k${RST}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# 費用
# ═══════════════════════════════════════════════════════════════

cost_val="${cost:-0}"
cost_fmt=$(printf '%.2f' "$cost_val" 2>/dev/null || echo "0.00")
to_int "$cost_val" cost_int

if (( cost_int >= 10 )); then cost_color="$RED"
elif (( cost_int >= 5 )); then cost_color="$YELLOW"
elif [[ "$cost_fmt" == "0.00" ]]; then cost_color="$GRAY"
else cost_color="$YELLOW"; fi

# ═══════════════════════════════════════════════════════════════
# 經過時間（零值智慧隱藏）
# ═══════════════════════════════════════════════════════════════

to_int "${duration_ms:-0}" dur_ms
dur_section=""
if (( dur_ms > 0 )); then
  dur_sec=$((dur_ms / 1000))
  dur_min=$((dur_sec / 60))
  dur_s=$((dur_sec % 60))
  # 格式化後仍為 0m0s 就不顯示（session 啟動初期 dur_ms 可能是幾百毫秒）
  if (( dur_min > 0 || dur_s > 0 )); then
    dur_section="${SEP}${GRAY}${S_TIME}${dur_min}m${dur_s}s${RST}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Git 分支與髒標記（帶快取）
# ═══════════════════════════════════════════════════════════════

GIT_CACHE_MAX_AGE=5

# One cache file per user and per directory. A single shared path meant that
# concurrent sessions in different projects overwrote each other's entry and
# displayed the wrong branch, and on a multi-user host the first user to create
# /tmp/claude-statusline-git-cache made the write fail for everybody else.
GIT_CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-${UID:-0}"
mkdir -p "$GIT_CACHE_DIR" 2>/dev/null || true
GIT_CACHE="$GIT_CACHE_DIR/git-$(cksum <<< "${cwd_full:-.}" | cut -d' ' -f1)"

git_branch="${branch:-}"
dirty=""

git_cache_is_stale() {
  [[ -f "$GIT_CACHE" ]] || return 0
  local mtime now
  # mtime: GNU coreutils spells it -c %Y, BSD/macOS spells it -f %m.
  # On Linux `stat -f` reports *filesystem* status and treats %m as a file
  # name, so it printed noise on stdout ('  File: "..."'). That noise reached
  # the arithmetic expansion and `set -u` aborted the whole script with
  # "File: unbound variable" -- the status line went blank on every render
  # after the first one, since the guard above returns early only while the
  # cache file is still missing.
  mtime=$(stat -c %Y "$GIT_CACHE" 2>/dev/null || stat -f %m "$GIT_CACHE" 2>/dev/null || echo 0)
  to_int "$mtime" mtime
  now=$(date +%s)
  (( now - mtime > GIT_CACHE_MAX_AGE ))
}

if [[ -n "${cwd_full:-}" && -d "${cwd_full:-}" ]]; then
  if git_cache_is_stale; then
    if git -C "$cwd_full" rev-parse --git-dir &>/dev/null; then
      cached_branch="${git_branch}"
      if [[ -z "$cached_branch" ]]; then
        cached_branch=$(git -C "$cwd_full" -c core.useBuiltinFSMonitor=false branch --show-current 2>/dev/null) || true
        if [[ -z "$cached_branch" ]]; then
          cached_branch=$(git -C "$cwd_full" rev-parse --short HEAD 2>/dev/null) || true
        fi
      fi
      cached_dirty=""
      if ! git -C "$cwd_full" -c core.useBuiltinFSMonitor=false diff --quiet 2>/dev/null || \
         ! git -C "$cwd_full" -c core.useBuiltinFSMonitor=false diff --cached --quiet 2>/dev/null; then
        cached_dirty="*"
      fi
      echo "${cached_branch}|${cached_dirty}" > "$GIT_CACHE" 2>/dev/null || true
    else
      echo "|" > "$GIT_CACHE" 2>/dev/null || true
    fi
  fi

  if [[ -f "$GIT_CACHE" ]]; then
    IFS='|' read -r cached_br cached_dt < "$GIT_CACHE" || true
    sanitize cached_br
    if [[ -z "$git_branch" ]]; then git_branch="${cached_br}"; fi
    dirty="${cached_dt}"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# 行數增減（零值智慧隱藏）
# ═══════════════════════════════════════════════════════════════

to_int "${lines_add:-0}" lines_add
to_int "${lines_rm:-0}" lines_rm
lines_section=""
if (( lines_add > 0 || lines_rm > 0 )); then
  lines_section="${GREEN}+${lines_add}${RST}/${RED}-${lines_rm}${RST}"
fi

# ═══════════════════════════════════════════════════════════════
# 速率限制（條件顯示）
# ═══════════════════════════════════════════════════════════════

rate_section=""
to_int "${rate5h:--1}" rate5h_int
to_int "${rate7d:--1}" rate7d_int

rate5h_reset_fmt=$(reset_clock "${rate5h_reset:-}")
rate7d_reset_fmt=$(reset_countdown "${rate7d_reset:-}")

rate_parts=""
if (( rate5h_int >= 0 )); then
  if (( rate5h_int >= 80 )); then rate_parts+="${RED}5h:${rate5h_int}%${RST}"
  else rate_parts+="${GRAY}5h:${rate5h_int}%${RST}"; fi
  if [[ -n "$rate5h_reset_fmt" ]]; then
    rate_parts+=" ${GRAY}${S_RESET}${rate5h_reset_fmt}${RST}"
  fi
fi
if (( rate7d_int >= 0 )); then
  if [[ -n "$rate_parts" ]]; then
    if [[ -n "$rate5h_reset_fmt" ]]; then rate_parts+="  "; else rate_parts+=" "; fi
  fi
  if (( rate7d_int >= 80 )); then rate_parts+="${RED}7d:${rate7d_int}%${RST}"
  else rate_parts+="${GRAY}7d:${rate7d_int}%${RST}"; fi
  if [[ -n "$rate7d_reset_fmt" ]]; then
    rate_parts+=" ${GRAY}${S_RESET}${rate7d_reset_fmt}${RST}"
  fi
fi
if [[ -n "$rate_parts" ]]; then
  rate_section="${SEP}${rate_parts}"
fi

# ═══════════════════════════════════════════════════════════════
# 動態提示符（顏色跟上下文用量連動）
# ═══════════════════════════════════════════════════════════════

if (( pct_int >= 90 )); then prompt_color="$RED"
elif (( pct_int >= 70 )); then prompt_color="$YELLOW"
else prompt_color="$GREEN"; fi

# ═══════════════════════════════════════════════════════════════
# 組裝第一行
# ═══════════════════════════════════════════════════════════════

line1="${PURPLE}${S_BRAND}${RST} ${CYAN}${model}${RST}"
line1+="${SEP}${bar} ${pct_color}${pct_int}%${RST}${ctx_warn}${ctx_label}"
line1+="${SEP}${cost_color}${S_COST}\$${cost_fmt}${RST}"
line1+="${dur_section}"
line1+="${rate_section}"

# ═══════════════════════════════════════════════════════════════
# 組裝第二行
# ═══════════════════════════════════════════════════════════════

parts=()
if [[ -n "$git_branch" ]]; then
  parts+=("${GRAY}${S_BRANCH}${git_branch}${dirty}${RST}")
fi
if [[ -n "$lines_section" ]]; then
  parts+=("${lines_section}")
fi
parts+=("${BLUE}${dir}${RST}")

# Agent / Worktree 指示器（僅在非主 session 時顯示）
if [[ -n "${wt_name:-}" ]]; then
  parts+=("${YELLOW}⚙ worktree:${wt_name}${RST}")
elif [[ -n "${agent_name:-}" ]]; then
  parts+=("${YELLOW}⚙ ${agent_name}${RST}")
fi

line2=""
for i in "${!parts[@]}"; do
  if (( i > 0 )); then
    line2+="${SEP}"
  fi
  line2+="${parts[$i]}"
done

# ═══════════════════════════════════════════════════════════════
# 輸出
# ═══════════════════════════════════════════════════════════════

# 只輸出兩行（Claude Code 有自己的輸入提示符，不需要我們的 ❯）
printf '%s
%s' "$line1" "$line2"
