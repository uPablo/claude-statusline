#!/usr/bin/env bash
# claude-statusline — portable status line for Claude Code (macOS · Linux · Windows Git Bash/WSL)
# L1 code:   dir:branch STATE ●N↑N↓N⚑N (owner/repo) · lang ver · +adds/-dels
# L2 claude: model · think · $cost · $burn/h · day $daily · ⏱dur · chips
# L3 limits: ctx · 5h · wk · opus · sonnet  (all with ↻reset · abs)
# L4 system: mem · disk · bat · cpu · clock · email
export LC_NUMERIC=C
input=$(cat)
printf '%s' "$input" > "${TMPDIR:-/tmp}/cc-statusline-payload.json" 2>/dev/null || true

# --- Platform detection ---
OS=$(uname -s 2>/dev/null)
IS_MAC=0; IS_GNU=0
[ "$OS" = "Darwin" ] && IS_MAC=1
date --version >/dev/null 2>&1 && IS_GNU=1   # GNU coreutils (Linux, Git Bash, WSL)

jqr() { echo "$input" | jq -r "$1 // empty" 2>/dev/null; }

# --- Payload ---
cwd=$(jqr '.workspace.current_dir // .cwd')
git_worktree=$(jqr '.worktree.name // .workspace.git_worktree')
model=$(jqr '.model.display_name // .model')
session_id=$(jqr '.session_id')
ctx_pct=$(jqr '.context_window.used_percentage')
ctx_size=$(jqr '.context_window.context_window_size')
session_cost=$(jqr '.cost.total_cost_usd')
duration_ms=$(jqr '.cost.total_duration_ms')
lines_add=$(jqr '.cost.total_lines_added')
lines_del=$(jqr '.cost.total_lines_removed')
rl_5h=$(jqr '.rate_limits.five_hour.used_percentage')
reset_5h=$(jqr '.rate_limits.five_hour.resets_at')
rl_7d=$(jqr '.rate_limits.seven_day.used_percentage')
reset_7d=$(jqr '.rate_limits.seven_day.resets_at')
rl_opus=$(jqr '.rate_limits.seven_day_opus.used_percentage')
reset_opus=$(jqr '.rate_limits.seven_day_opus.resets_at')
rl_sonnet=$(jqr '.rate_limits.seven_day_sonnet.used_percentage')
reset_sonnet=$(jqr '.rate_limits.seven_day_sonnet.resets_at')
ostyle=$(jqr '.output_style.name')
vimmode=$(jqr '.vim.mode')
ccver=$(jqr '.version')
effort=$(jqr '.effort.level')
[ -z "$effort" ] && effort=$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)
account=$(jq -r '.oauthAccount.emailAddress // empty' ~/.claude.json 2>/dev/null)
ctx_tokens=$(echo "$input" | jq -r '
  .context_window.current_usage as $u
  | if ($u|type)=="number" then $u
    elif ($u|type)=="object" then (($u.input_tokens//0)+($u.output_tokens//0)+($u.cache_creation_input_tokens//0)+($u.cache_read_input_tokens//0))
    else empty end' 2>/dev/null)
cache_read=$(jqr '.context_window.current_usage.cache_read_input_tokens')

# --- Colors ---
C_CTX=$'\033[38;5;39m'; C_5H=$'\033[38;5;214m'; C_WK=$'\033[38;5;170m'
C_OPUS=$'\033[38;5;135m'; C_SONNET=$'\033[38;5;73m'
C_COST=$'\033[38;5;42m'; C_MEM=$'\033[38;5;75m'; C_DISK=$'\033[38;5;80m'; C_EFFORT=$'\033[38;5;141m'
C_ADD=$'\033[38;5;78m'; C_DEL=$'\033[38;5;203m'; C_WARN=$'\033[38;5;208m'; C_OK=$'\033[38;5;42m'
C_LANG=$'\033[38;5;113m'; C_BURN=$'\033[38;5;215m'
C_DIM=$'\033[2m'; C_RESET=$'\033[0m'

BAR_WIDTH=6
ISEP=" ${C_DIM}·${C_RESET} "
WD=(dom seg ter qua qui sex sáb)

# --- Portable helpers (date / stat / sha differ across platforms) ---
epoch_fmt()  { if [ "$IS_GNU" = 1 ]; then date -d "@$1" "+$2" 2>/dev/null; else date -r "$1" "+$2" 2>/dev/null; fi; }
file_mtime() { if [ "$IS_GNU" = 1 ]; then stat -c %Y "$1" 2>/dev/null; else stat -f %m "$1" 2>/dev/null; fi; }
sha1()       { if command -v shasum >/dev/null 2>&1; then shasum; else sha1sum 2>/dev/null; fi; }

make_bar() {
  local pct color filled empty bar i
  pct=$(printf '%.0f' "$1"); color="$2"
  [ "$pct" -gt 100 ] && pct=100; [ "$pct" -lt 0 ] && pct=0
  filled=$(( (pct * BAR_WIDTH + 50) / 100 )); [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
  empty=$((BAR_WIDTH - filled)); bar=""
  for ((i = 0; i < filled; i++)); do bar+="▰"; done
  for ((i = 0; i < empty; i++)); do bar+="▱"; done
  printf '%s▕%s%s%s%s%s▏%s' "$C_DIM" "$C_RESET" "$color" "$bar" "$C_RESET" "$C_DIM" "$C_RESET"
}
seg() {
  local label="$1" color="$2" pct="$3" suffix="$4" chunk
  chunk=$(printf '%s%s%s%s%s%%' "$color" "$label" "$C_RESET" "$(make_bar "$pct" "$color")" "$(printf '%.0f' "$pct")")
  [ -n "$suffix" ] && chunk="${chunk} ${C_DIM}${suffix}${C_RESET}"
  printf '%s' "$chunk"
}
to_epoch() {
  local raw="$1" clean epoch
  { [ -z "$raw" ] || [ "$raw" = "null" ]; } && return
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    epoch=$raw; [ "$epoch" -gt 100000000000 ] && epoch=$((epoch / 1000))
  elif [ "$IS_GNU" = 1 ]; then
    epoch=$(date -u -d "$raw" +%s 2>/dev/null)
  elif [[ "$raw" == *Z ]]; then
    clean=${raw%Z}; clean=${clean%%.*}; epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null)
  else
    clean=${raw%%.*}; epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null)
  fi
  [ -n "$epoch" ] && printf '%s' "$epoch"
}
reset_label() {
  local epoch now diff d h m abs widx eta
  epoch=$(to_epoch "$1"); [ -z "$epoch" ] && return
  now=$(date +%s); diff=$((epoch - now)); [ "$diff" -lt 0 ] && diff=0
  d=$((diff / 86400)); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then eta=$(printf '%dd%dh' "$d" "$h")
  elif [ "$h" -gt 0 ]; then eta=$(printf '%dh%dm' "$h" "$m")
  else eta=$(printf '%dm' "$m"); fi
  if [ "$diff" -lt 86400 ]; then abs=$(epoch_fmt "$epoch" %H:%M)
  else widx=$(epoch_fmt "$epoch" %w); abs="${WD[$widx]} $(epoch_fmt "$epoch" %H:%M)"; fi
  printf '↻%s · %s' "$eta" "$abs"
}
fmt_dur() { local s="$1" h m; h=$((s/3600)); m=$(((s%3600)/60)); [ "$h" -gt 0 ] && printf '%dh%dm' "$h" "$m" || printf '%dm' "$m"; }
human() { awk -v n="$1" 'BEGIN{ if(n>=1000000){v=n/1000000; if(v==int(v))printf "%dM",v; else printf "%.1fM",v} else if(n>=1000)printf "%.0fk",n/1000; else printf "%d",n }'; }
gib()   { awk -v b="$1" 'BEGIN{ printf "%.1fG", b/1073741824 }'; }

# --- Session wall-clock ---
dur=""
if [ -n "$session_id" ]; then
  sf="${TMPDIR:-/tmp}/cc-sl-sess-${session_id}"
  [ -f "$sf" ] || date +%s > "$sf"
  start=$(cat "$sf" 2>/dev/null); [ -n "$start" ] && dur=$(fmt_dur $(( $(date +%s) - start )))
elif [ -n "$duration_ms" ]; then dur=$(fmt_dur $((duration_ms / 1000))); fi

# --- ccusage burn rate + daily cost (cached 60s) ---
burn=""; daily=""
cc_cache="${TMPDIR:-/tmp}/cc-sl-ccusage.txt"
cc_age=99999; [ -f "$cc_cache" ] && cc_age=$(( $(date +%s) - $(file_mtime "$cc_cache") ))
if [ "$cc_age" -gt 60 ] && command -v ccusage >/dev/null 2>&1; then
  b=$(perl -e 'alarm shift; exec @ARGV' 4 ccusage blocks --active --json 2>/dev/null | jq -r '.blocks[0].burnRate.costPerHour // empty' 2>/dev/null)
  dd=$(perl -e 'alarm shift; exec @ARGV' 4 ccusage daily --json 2>/dev/null | jq -r '(.daily // [] | sort_by(.date) | last | .totalCost) // empty' 2>/dev/null)
  printf '%s\n%s\n' "$b" "$dd" > "$cc_cache"
fi
burn=$(sed -n 1p "$cc_cache" 2>/dev/null); daily=$(sed -n 2p "$cc_cache" 2>/dev/null)

# --- Memory (mac: vm_stat · linux/wsl: /proc/meminfo) ---
mem_pct=""; mem_label=""; mem_total=""; mem_used=""
if [ "$IS_MAC" = 1 ]; then
  if mem_total=$(sysctl -n hw.memsize 2>/dev/null) && [ -n "$mem_total" ]; then
    ps=$(sysctl -n hw.pagesize 2>/dev/null)
    mem_used=$(vm_stat 2>/dev/null | awk -v ps="$ps" '/Pages active/{a=$3}/Pages wired/{w=$4}/occupied by compressor/{c=$5}END{gsub(/\./,"",a);gsub(/\./,"",w);gsub(/\./,"",c);print (a+w+c)*ps}')
  fi
elif [ -r /proc/meminfo ]; then
  read -r mem_total mem_used < <(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%d %d", t*1024, (t-a)*1024}' /proc/meminfo)
fi
if [ -n "$mem_total" ] && [ -n "$mem_used" ] && [ "$mem_used" -gt 0 ] 2>/dev/null; then
  mem_pct=$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN{printf "%.0f", u/t*100}'); mem_label="$(gib "$mem_used")/$(gib "$mem_total")"
fi

# --- Disk (POSIX df) ---
disk_pct=""; disk_label=""
read -r dcap davail < <(df -Pk / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5, $4}')
[ -n "$dcap" ] && { disk_pct=$dcap; disk_label="$(gib $((davail * 1024))) free"; }

# --- Battery (mac: pmset · linux: /sys/class/power_supply) ---
bat_pct=""; bat_chg=""; bat_col="$C_OK"
if [ "$IS_MAC" = 1 ]; then
  batt=$(pmset -g batt 2>/dev/null)
  if [ -n "$batt" ]; then
    bat_pct=$(echo "$batt" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
    case "$(echo "$batt" | grep -Ewo 'charging|discharging|charged|finishing' | head -1)" in charging|charged|finishing) bat_chg="⚡";; esac
  fi
else
  for b in /sys/class/power_supply/BAT*; do
    [ -r "$b/capacity" ] || continue
    bat_pct=$(cat "$b/capacity" 2>/dev/null)
    case "$(cat "$b/status" 2>/dev/null)" in Charging|Full) bat_chg="⚡";; esac
    break
  done
fi
if [ -n "$bat_pct" ]; then
  [ "$bat_pct" -lt 50 ] 2>/dev/null && bat_col="$C_5H"; [ "$bat_pct" -lt 20 ] 2>/dev/null && bat_col="$C_DEL"
fi

# --- CPU load (mac: sysctl · linux: /proc/loadavg) ---
if [ "$IS_MAC" = 1 ]; then
  load1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{gsub(/,/,"."); print $2}')
  cores=$(sysctl -n hw.ncpu 2>/dev/null)
else
  load1=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
  cores=$(nproc 2>/dev/null)
fi
cpu_col=$(awk -v l="${load1:-0}" -v c="${cores:-1}" -v g="$C_OK" -v a="$C_5H" -v r="$C_DEL" 'BEGIN{if(c<=0)c=1; x=l/c; if(x>=1)print r; else if(x>=0.7)print a; else print g}')

# --- Language / runtime (emoji + real version, multi-language, cached per dir) ---
build_lang_path() {
  local pin nb
  if   [ -f "$cwd/.nvmrc" ];        then pin=$(head -n1 "$cwd/.nvmrc" 2>/dev/null | tr -dc '0-9.')
  elif [ -f "$cwd/.node-version" ]; then pin=$(head -n1 "$cwd/.node-version" 2>/dev/null | tr -dc '0-9.')
  elif [ -f "$cwd/.tool-versions" ];then pin=$(grep -E '^nodejs? ' "$cwd/.tool-versions" 2>/dev/null | awk '{print $2}')
  fi
  [ -z "$pin" ] && pin=$(cat "$HOME/.nvm/alias/default" 2>/dev/null)
  pin=${pin#v}
  if [ -n "$pin" ]; then
    if [ -d "$HOME/.nvm/versions/node/v$pin/bin" ]; then nb="$HOME/.nvm/versions/node/v$pin/bin"
    else nb=$(ls -d "$HOME"/.nvm/versions/node/v"$pin"* 2>/dev/null | sort -V | tail -1); [ -n "$nb" ] && nb="$nb/bin"; fi
  fi
  printf '%s' "${nb:+$nb:}/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:/usr/bin:/bin"
}
compute_langs() {
  [ -z "$cwd" ] && return
  local out="" ver lp; lp="$(build_lang_path)"; local PATH="$lp"
  addl() { out="${out:+$out  }$1"; }
  vchunk() { printf '%s' "$1${2:+ ${C_LANG}${2}${C_RESET}}"; }
  { [ -f "$cwd/package.json" ] || [ -f "$cwd/.nvmrc" ] || [ -f "$cwd/.node-version" ] || [ -d "$cwd/node_modules" ]; } && { ver=$(node -v 2>/dev/null); addl "$(vchunk ⬢ "${ver#v}")"; }
  { [ -f "$cwd/composer.json" ] || [ -f "$cwd/artisan" ] || ls "$cwd"/*.php >/dev/null 2>&1; } && { ver=$(php -r 'echo PHP_VERSION;' 2>/dev/null); addl "$(vchunk 🐘 "$ver")"; }
  { [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/requirements.txt" ] || [ -f "$cwd/setup.py" ] || [ -f "$cwd/.python-version" ] || [ -f "$cwd/Pipfile" ]; } && { ver=$(python3 -V 2>&1 | awk '{print $2}'); addl "$(vchunk 🐍 "$ver")"; }
  [ -f "$cwd/go.mod" ]      && { ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//'); addl "$(vchunk 🐹 "$ver")"; }
  { [ -f "$cwd/Gemfile" ] || [ -f "$cwd/.ruby-version" ]; } && { ver=$(ruby -v 2>/dev/null | awk '{print $2}'); addl "$(vchunk 💎 "$ver")"; }
  [ -f "$cwd/Cargo.toml" ]  && { ver=$(rustc --version 2>/dev/null | awk '{print $2}'); addl "$(vchunk 🦀 "$ver")"; }
  [ -f "$cwd/bun.lockb" ]   && { ver=$(bun -v 2>/dev/null); addl "$(vchunk 🥟 "$ver")"; }
  { [ -f "$cwd/deno.json" ] || [ -f "$cwd/deno.jsonc" ]; } && { ver=$(deno --version 2>/dev/null | head -1 | awk '{print $2}'); addl "$(vchunk 🦕 "$ver")"; }
  printf '%s' "$out"
}
langline=""
if [ -n "$cwd" ]; then
  lkey=$(printf '%s' "$cwd" | sha1 | awk '{print $1}')
  lcache="${TMPDIR:-/tmp}/cc-sl-lang-${lkey}.txt"
  lage=99999; [ -f "$lcache" ] && lage=$(( $(date +%s) - $(file_mtime "$lcache") ))
  [ "$lage" -gt 600 ] && compute_langs > "$lcache" 2>/dev/null
  langline=$(cat "$lcache" 2>/dev/null)
fi

# --- Identity + git ---
dir=""; [ -n "$cwd" ] && dir=$(basename "$cwd")
branch=""; gitstate=""; repo=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  changed=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | grep -c '^')
  ahead=$(git -C "$cwd" --no-optional-locks rev-list --count '@{u}..HEAD' 2>/dev/null)
  behind=$(git -C "$cwd" --no-optional-locks rev-list --count 'HEAD..@{u}' 2>/dev/null)
  stash=$(git -C "$cwd" --no-optional-locks stash list 2>/dev/null | grep -c '^')
  gdir=$(git -C "$cwd" --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)
  gst=""
  if   [ -d "$gdir/rebase-merge" ] || [ -d "$gdir/rebase-apply" ]; then gst=REBASE
  elif [ -f "$gdir/MERGE_HEAD" ];       then gst=MERGE
  elif [ -f "$gdir/CHERRY_PICK_HEAD" ]; then gst=CHERRY
  elif [ -f "$gdir/REVERT_HEAD" ];      then gst=REVERT
  elif [ -f "$gdir/BISECT_LOG" ];       then gst=BISECT
  fi
  repo=$(git -C "$cwd" --no-optional-locks remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[/:]([^/]+/[^/]+)$#\1#')
  [ -n "$gst" ] && gitstate="${C_DEL}${gst}${C_RESET} "
  if [ "${changed:-0}" -gt 0 ] 2>/dev/null; then gitstate="${gitstate}${C_WARN}●${changed}${C_RESET}"; else gitstate="${gitstate}${C_OK}✓${C_RESET}"; fi
  [ -n "$ahead" ]  && [ "$ahead" -gt 0 ] 2>/dev/null  && gitstate="${gitstate} ${C_DIM}↑${ahead}${C_RESET}"
  [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null && gitstate="${gitstate} ${C_DIM}↓${behind}${C_RESET}"
  [ "${stash:-0}" -gt 0 ] 2>/dev/null && gitstate="${gitstate} ${C_DIM}⚑${stash}${C_RESET}"
fi
ident="$dir"
if [ -n "$branch" ]; then
  ident="${ident:+${ident}${C_DIM}:${C_RESET}}${branch}"
  [ -n "$gitstate" ] && ident="${ident} ${gitstate}"
  [ -n "$repo" ] && ident="${ident} ${C_DIM}(${repo})${C_RESET}"
fi
[ -n "$git_worktree" ] && ident="${ident}${C_DIM}[${git_worktree}]${C_RESET}"

# --- L1: code ---
line1="$ident"
[ -n "$langline" ] && line1="${line1}${ISEP}${langline}"
if { [ -n "$lines_add" ] && [ "$lines_add" -gt 0 ] 2>/dev/null; } || { [ -n "$lines_del" ] && [ "$lines_del" -gt 0 ] 2>/dev/null; }; then
  line1="${line1}${ISEP}${C_ADD}+$(human "${lines_add:-0}")${C_RESET}${C_DIM}/${C_RESET}${C_DEL}-$(human "${lines_del:-0}")${C_RESET}"
fi

# --- L2: claude session ---
line2=""; a2() { [ -n "$line2" ] && line2="${line2}${ISEP}"; line2="${line2}$1"; }
[ -n "$model" ]  && a2 "$model"
[ -n "$effort" ] && a2 "${C_DIM}think:${C_RESET}${C_EFFORT}${effort}${C_RESET}"
[ -n "$session_cost" ] && a2 "${C_COST}\$$(printf '%.2f' "$session_cost")${C_RESET}"
[ -n "$burn" ]  && a2 "${C_BURN}\$$(printf '%.1f' "$burn")/h${C_RESET}"
[ -n "$daily" ] && a2 "${C_DIM}day ${C_RESET}${C_COST}\$$(printf '%.0f' "$daily")${C_RESET}"
[ -n "$dur" ]   && a2 "${C_DIM}⏱${dur}${C_RESET}"
chips=""
[ -n "$ostyle" ] && [ "$ostyle" != "default" ] && chips="${chips:+${chips} }${ostyle}"
[ -n "$vimmode" ] && chips="${chips:+${chips} }${vimmode}"
[ -n "$ccver" ] && chips="${chips:+${chips} }v${ccver}"
[ -n "$chips" ] && a2 "${C_DIM}${chips}${C_RESET}"

# --- L3: context + all limits ---
ctx_suffix=""
if [ -n "$ctx_pct" ]; then
  [ -z "$ctx_tokens" ] && [ -n "$ctx_size" ] && ctx_tokens=$(awk -v p="$ctx_pct" -v s="$ctx_size" 'BEGIN{printf "%d", p/100*s}')
  [ -n "$ctx_tokens" ] && [ -n "$ctx_size" ] && ctx_suffix="$(human "$ctx_tokens")/$(human "$ctx_size")"
  [ -n "$cache_read" ] && [ -n "$ctx_tokens" ] && [ "$ctx_tokens" -gt 0 ] 2>/dev/null && ctx_suffix="${ctx_suffix} cache$(awk -v c="$cache_read" -v t="$ctx_tokens" 'BEGIN{printf "%.0f", c/t*100}')%"
fi
line3=""; a3() { [ -n "$line3" ] && line3="${line3}${ISEP}"; line3="${line3}$1"; }
[ -n "$ctx_pct" ]   && a3 "$(seg ctx "$C_CTX" "$ctx_pct" "$ctx_suffix")"
[ -n "$rl_5h" ]     && a3 "$(seg 5h "$C_5H" "$rl_5h" "$(reset_label "$reset_5h")")"
[ -n "$rl_7d" ]     && a3 "$(seg wk "$C_WK" "$rl_7d" "$(reset_label "$reset_7d")")"
[ -n "$rl_opus" ]   && a3 "$(seg opus "$C_OPUS" "$rl_opus" "$(reset_label "$reset_opus")")"
[ -n "$rl_sonnet" ] && a3 "$(seg sonnet "$C_SONNET" "$rl_sonnet" "$(reset_label "$reset_sonnet")")"

# --- L4: system ---
line4=""; a4() { [ -n "$line4" ] && line4="${line4}${ISEP}"; line4="${line4}$1"; }
[ -n "$mem_pct" ]  && a4 "$(seg mem "$C_MEM" "$mem_pct" "$mem_label")"
[ -n "$disk_pct" ] && a4 "$(seg disk "$C_DISK" "$disk_pct" "$disk_label")"
[ -n "$bat_pct" ]  && a4 "${C_DIM}bat${C_RESET} ${bat_col}${bat_pct}%${bat_chg}${C_RESET}"
[ -n "$load1" ]    && a4 "${C_DIM}cpu${C_RESET} ${cpu_col}${load1}${C_RESET}"
a4 "${C_DIM}$(date +%H:%M)${C_RESET}"
[ -n "$account" ]  && a4 "${C_DIM}${account}${C_RESET}"

printf '%s' "$line1"
for L in "$line2" "$line3" "$line4"; do [ -n "$L" ] && printf '\n%s' "$L"; done
