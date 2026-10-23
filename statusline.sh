#!/bin/bash
# Claude Code status line, most important first:
#   ctx █░░░░░░░ 14% 141k/1M │ 5h 7% reset 3h 29m, ends 20% (3.6%/h) │ wk 61% reset 2d 12h, ends 91% (0.5%/h) │ Opus 5.5 xhigh │ folder
# Values are bold white while fine, amber from 50%, bold red from 80%. Each limit shows the time to reset, where
# the current trend ends it, and the pace now; "out 1d 11h (0.9%/h)" when it gets to 100% first, "full" once there.
# Claude Code pipes the session as JSON on stdin and shows what this prints.

input=$(cat)

# One jq pass; fields joined by \x1f so empty ones survive `read`.
IFS=$'\x1f' read -r model effort dir size used pct transcript fh_pct fh_reset wk_pct wk_reset session < <(jq -r '
  def tokens: (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0);
  [ (.model.display_name // "Claude"),
    (.effort.level // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.context_window_size // ""),
    (.context_window.current_usage | if type == "object" then tokens else "" end),
    (.context_window.used_percentage // ""),
    (.transcript_path // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // "" | if type == "number" then floor else . end),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // "" | if type == "number" then floor else . end),
    (.session_name // "" | gsub("[\\s\u001f]+"; " ") | ltrimstr(" ") | rtrimstr(" "))
  ] | map(tostring) | join("\u001f")' <<<"$input")

# Older Claude Code builds send no context_window: read the last main-thread usage from the transcript.
if [[ -z $used && -f $transcript ]]; then
  used=$(tail -n 400 "$transcript" | jq -R -r '
    fromjson? | select(.message.usage? and (.isSidechain | not)) | .message.usage
    | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)' 2>/dev/null | tail -n 1)
fi

size=${size:-200000}
if [[ -z $pct && -n $used ]]; then
  pct=$(( used * 100 / size ))
fi

now=$(date +%s)

# When this session last heard from the API. Usage limits arrive at the start of each reply and an idle
# session keeps reporting what it last heard, so this says how fresh its readings are: the time of the
# request behind its last reply in the transcript (the reply itself is written once its first block is
# done, which can be minutes later), or the reply's own time if the request isn't logged. Empty when
# unknown. macOS tail -c takes ~35 ms per MB, so look at the last 300 KB first.
seen=""
if [[ -f $transcript ]]; then
  for bytes in 300000 3000000; do
    seen=$(tail -c "$bytes" "$transcript" 2>/dev/null | grep -F -e '"type":"assistant"' -e '"type":"api-request"' | jq -R -r -n '
      [inputs | fromjson? | select(.type == "assistant" or .type == "api-request")] as $lines
      | ($lines | map(select(.type == "api-request") | {key: (.id | tostring), value: .timestamp}) | from_entries) as $requests
      | ($lines | map(select(.type == "assistant")) | last) as $reply
      | select($reply != null) | ($requests[$reply.requestRef // ""] // $reply.timestamp)
      | try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | floor) catch empty' 2>/dev/null)
    [[ -n $seen ]] && break
  done
fi

# Explicit 256-colour palette (no faint/dim text, which Terminal.app fades into the background),
# picked by the macOS appearance so it reads on both dark and light terminal backgrounds.
dark=0
if [[ $(defaults read -g AppleInterfaceStyle 2>/dev/null) == Dark ]] || ! command -v defaults >/dev/null; then dark=1; fi
if (( dark )); then
  c_label=$'\e[38;5;250m'; c_sec=$'\e[38;5;248m'; c_sep=$'\e[38;5;242m'
  c_val=$'\e[1;97m'; c_warn=$'\e[1;38;5;220m'; c_crit=$'\e[1;38;5;203m'
  c_bar=$'\e[38;5;75m'; c_empty=$'\e[38;5;240m'; c_effort=$'\e[38;5;141m'
  c_time=$'\e[38;5;153m'; true_time=$'\e[38;2;177;185;249m'
else
  c_label=$'\e[38;5;240m'; c_sec=$'\e[38;5;242m'; c_sep=$'\e[38;5;249m'
  c_val=$'\e[1;38;5;16m'; c_warn=$'\e[1;38;5;130m'; c_crit=$'\e[1;38;5;160m'
  c_bar=$'\e[38;5;25m'; c_empty=$'\e[38;5;252m'; c_effort=$'\e[38;5;91m'
  c_time=$'\e[38;5;105m'; true_time=$'\e[38;2;87;105;247m'
fi
# Reset times in the colour Claude Code gives inline code (its theme's "permission" colour). Claude Code
# draws 256 colours in Terminal.app whatever COLORTERM says, so match its rgb-to-256 mapping there (153 / 105)
# and use the exact rgb only in other terminals that take 24-bit colour.
[[ ${TERM_PROGRAM:-} != Apple_Terminal && ( ${COLORTERM:-} == truecolor || ${COLORTERM:-} == 24bit ) ]] && c_time=$true_time

# "Chat (auto)" theme. Claude Code's custom themes have a fixed base (no auto), so keep
# ~/.claude/themes/chat-auto.json a copy of chat-dark or chat-light matching the macOS appearance; Claude Code
# watches that folder and applies the change live. Writes only when the appearance flips; delete the file to stop.
themes=$HOME/.claude/themes
if [[ -f $themes/chat-auto.json ]]; then
  src=$themes/chat-light.json; (( dark )) && src=$themes/chat-dark.json
  if [[ -f $src ]]; then
    want=$(jq '.name = "Chat (auto)"' "$src" 2>/dev/null)
    if [[ -n $want && $want != "$(<"$themes/chat-auto.json")" ]]; then
      tmp="$themes/.chat-auto.$$"  # no .json extension, so Claude Code never loads it as a theme
      printf '%s\n' "$want" >"$tmp" && mv -f "$tmp" "$themes/chat-auto.json"
    fi
  fi
fi
rst=$'\e[0m'; sep=" ${c_sep}│${rst} "

short() {
  awk -v n="$1" 'BEGIN { if (n >= 1000000) printf "%gM", int(n / 100000) / 10; else if (n >= 1000) printf "%dk", n / 1000; else printf "%d", n }'
}

# Bold value colour while fine, warning colour from 50%, critical from 80%.
level() {
  if (( $1 >= 80 )); then printf '%s' "$c_crit"; elif (( $1 >= 50 )); then printf '%s' "$c_warn"; else printf '%s' "$c_val"; fi
}

# Seconds as 2d 4h / 3h 12m / 45m.
duration() {
  local s=$1
  (( s < 0 )) && s=0
  local d=$(( s / 86400 )) h=$(( s % 86400 / 3600 )) m=$(( s % 3600 / 60 ))
  if (( d > 0 )); then echo "${d}d ${h}h"; elif (( h > 0 )); then echo "${h}h ${m}m"; else echo "${m}m"; fi
}

hist_dir=${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline
mkdir -p "$hist_dir" 2>/dev/null

# History of "reset_epoch time used% seen" for the current window, shared by every session on this account
# (seen: when the reading came from the API). A sample is added when the value changes or every `every` seconds.
# Idle sessions keep reporting what they last heard, so a reading heard before the newest saved one is stale:
# it is skipped and the saved one shown. A fresher reading starts a new history when it is for another window,
# or when it is over a point lower in the same window: the limit was reset early (e.g. mid-week). Then
# "# start <time>" goes first, the last time the old value was heard, and the projection counts from there.
# Usage never falls within a window, so a fresh reading up to a point lower is timing noise between sessions
# and the saved value stands. Without a seen time, any reading below the saved one counts as stale.
# Prints "reset_epoch used%" of the freshest reading.
record() { # file used_percent reset_epoch every_seconds seen_epoch
  local file=$1 p=$2 reset=$3 every=$4 seen=$5 last_reset="" last_t="" last_p="" last_seen="" d start="" new=0 drop
  [[ -s $file ]] && read -r last_reset last_t last_p last_seen < <(awk '$1 != "#"' "$file" | tail -n 1)
  if [[ -n $last_reset ]]; then
    d=$(( reset - last_reset )); last_seen=${last_seen:-$last_t}
    drop=$(awk -v a="$p" -v b="$last_p" 'BEGIN { print (a < b - 1) ? "big" : (a < b) ? "small" : "none" }')
    if [[ -n $seen ]]; then
      # A window that is over can't be fresher than anything reported now.
      if (( seen < last_seen && last_reset > now )); then echo "$last_reset $last_p"; return; fi
      if (( d >= -600 && d <= 600 )); then
        if [[ $drop == big ]]; then start=$last_seen; new=1
        elif [[ $drop == small ]]; then echo "$last_reset $last_p"; return; fi
      fi
    else
      if (( d < -600 )); then echo "$reset $p"; return; fi
      if (( d <= 600 )) && [[ $drop != none ]]; then echo "$last_reset $last_p"; return; fi
    fi
    (( d < -600 || d > 600 )) && new=1
  fi
  local line
  line=$(printf '%s %s %s %s' "$reset" "$now" "$p" "${seen:-$now}")
  if (( new )); then
    # One write, so another session never reads the header without a sample after it.
    if [[ -n $start ]]; then printf '# start %s\n%s\n' "$start" "$line" >"$file"; else printf '%s\n' "$line" >"$file"; fi
  elif [[ -z $last_t || $p != "$last_p" ]] || (( now - last_t >= every )); then
    printf '%s\n' "$line" >>"$file"
  fi
  echo "$reset $p"
}

# Prints "seconds_to_100 percent_at_reset percent_per_hour": seconds until the limit reaches 100% (-1 if the
# fitted pace levels off first, 0 if already there), where the trend leaves usage when the window resets,
# and the fitted pace now.
# Weighted least squares over the window's history, recent samples weighted most (half-life given),
# anchored at 0% when the window opened (or at its "# start" after an early reset), so with no history yet
# it equals the window average.
# Quadratic once the history spans at least the time left to reset (a curve is never extrapolated
# further than it was observed); linear otherwise. A quadratic whose slope now is negative means usage
# has levelled off (a night does not do this, a day or two idle does), so the pace is taken as flat.
# The projection starts from the current value, using the fit's slope and curvature at now.
# Empty when the window opened under 10 minutes ago (too early to tell).
project() { # file used_percent reset_epoch window_seconds half_life_seconds
  awk -v p="$2" -v r="$3" -v w="$4" -v hl="$5" -v now="$now" '
    function add(t, y,   x, k) {
      x = (t - now) / 3600; k = exp(-log(2) * (now - t) / hl)
      S0 += k; S1 += k * x; S2 += k * x^2; S3 += k * x^3; S4 += k * x^4
      T0 += k * y; T1 += k * x * y; T2 += k * x^2 * y
    }
    function det(a, b, c, d, e, f, g, h, i) { return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g) }
    $1 == "#" { if ($2 == "start") s = $3; next }
    $2 < now { add($2, $3); n++; if (!first || $2 < first) first = $2 }
    END {
      start = r - w; if (s > start) start = s
      if (now - start < 600) exit
      add(start, 0); add(now, p)
      need = 100 - p
      if (need <= 0) { print 0, p, 0; exit }
      b = (S0 * T1 - S1 * T0) / (S0 * S2 - S1^2); c = 0
      D = det(S0, S1, S2, S1, S2, S3, S2, S3, S4)
      if (n >= 3 && now - first >= r - now && D > 1e-12 * S0 * S2 * S4) {
        bq = det(S0, T0, S2, S1, T1, S3, S2, T2, S4) / D
        cq = det(S0, S1, T0, S1, S2, T1, S2, S3, T2) / D
        if (bq >= 0) { b = bq; c = cq } else { b = 0; c = 0 }
      }
      # Value at reset: usage never goes down, so a curve that peaks first stays at its peak.
      H = (r - now) / 3600; if (H < 0) H = 0
      h = H
      if (c < 0) { top = -b / (2 * c); if (top < 0) top = 0; if (top < h) h = top }
      proj = p + b * h + c * h^2; if (proj < p) proj = p
      # Smallest positive root of c*h^2 + b*h = need, in a form that also holds for c = 0.
      disc = b^2 + 4 * c * need
      if (disc < 0 || b + sqrt(disc) <= 0) out = -1
      else out = int(2 * need / (b + sqrt(disc)) * 3600)
      printf "%d %.2f %.4f\n", out, proj, (b > 0 ? b : 0)
    }' "$1"
}

# Same output as project(), for the weekly limit: the pace you are on now, carried to the reset. The owner adjusts
# usage to what this shows, so recent hours count most (half-life given; 4 h follows a change of pace about half way
# in 4-5 h, the 1-day fit took 32 h, and was no more accurate in backtests). The reading only moves in whole
# percents, so the pace comes from when it went up: recency-weighted percents per hour over the intervals between
# steps. The time since the last step counts only once it is longer than the pace implies, as if a step happened
# now, so the pace eases down instead of see-sawing. Usage across a gap in the readings (no session running)
# is taken as spread evenly over it, so the last step in it lands gap/(2 x steps) before the reading. Usage now is the last step's crossing
# (a reading rounds, so it showed k at k - 0.5) plus the pace since, kept within half a point of the reading.
step_pace() { # file used_percent reset_epoch window_seconds half_life_seconds
  awk -v p="$2" -v r="$3" -v w="$4" -v hl="$5" -v now="$now" '
    $1 == "#" { if ($2 == "start") s = $3; next }
    $2 <= now && ($1 - r) * ($1 - r) <= 360000 { n++; t[n] = $2; y[n] = $3 }
    END {
      start = r - w; if (s > start) start = s
      if (now - start < 600) exit
      m = 0; st[0] = start; sy[0] = 0
      for (i = 1; i <= n; i++) if (t[i] > start && y[i] > sy[m]) {
        prev = (i > 1 && t[i - 1] > start) ? t[i - 1] : start
        c = (t[i] - prev > 1200) ? t[i] - (t[i] - prev) / (2 * (y[i] - sy[m])) : t[i]
        m++; st[m] = c; sy[m] = y[i]
      }
      if (p > sy[m]) { m++; st[m] = now; sy[m] = p }
      for (i = 1; i <= m; i++) {
        k = 2 ^ (-(now - (st[i - 1] + st[i]) / 2) / hl)
        num += k * (sy[i] - sy[i - 1]); den += k * (st[i] - st[i - 1]) / 3600
      }
      gap = (now - st[m]) / 3600; pace = den > 0 ? num / den : 0
      if (den <= 0 || gap * pace > 1) {
        k = 2 ^ (-(now - (st[m] + now) / 2) / hl); num += k; den += k * gap
        pace = den > 0 ? num / den : 0
      }
      cur = sy[m] - (m > 0 ? 0.5 : 0) + (pace * gap < 1 ? pace * gap : 1)
      if (cur > p + 0.5) cur = p + 0.5; if (cur < p - 0.5) cur = p - 0.5; if (cur < 0) cur = 0
      if (p >= 100) { print 0, p, 0; exit }
      H = (r - now) / 3600; if (H < 0) H = 0
      out = pace > 0 ? int((100 - cur) / pace * 3600) : -1
      printf "%d %.2f %.4f\n", out, cur + pace * H, pace
    }' "$1"
}

# Percent per hour as 12 / 0.6 / 0.04 / 0.
rate() {
  awk -v r="$1" 'BEGIN { if (r >= 9.95) printf "%d", r + 0.5; else if (r >= 0.095) printf "%.1f", r
    else if (r >= 0.005) printf "%.2f", r; else printf "0" }'
}

# "wk 61% reset 2d 12h, ends 91% (0.5%/h)", "wk 79% reset 1d 12h, out 1d 11h (1.8%/h)" when projected to
# run out first, "wk 100% reset 9h 5m, full" once it has. Nothing when the limit is not reported.
limit() { # label used_percent reset_epoch window_seconds sample_every_seconds half_life_seconds history_name estimator
  local label=$1 raw=$2 reset=$3 window=$4 every=$5 half_life=$6 name=$7 estimator=$8
  [[ -z $raw ]] && return
  local file="$hist_dir/$name.txt" p left out="" proj="" per_hour=""
  [[ -n $reset ]] && read -r reset raw < <(record "$file" "$raw" "$reset" "$every" "$seen")
  p=$(printf '%.0f' "$raw")
  printf '%s%s%s %s%s%%%s' "$c_label" "$label" "$rst" "$(level "$p")" "$p" "$rst"
  [[ -z $reset ]] && return
  left=$(( reset - now ))
  read -r out proj per_hour < <("$estimator" "$file" "$raw" "$reset" "$window" "$half_life")
  local left_s out_s="" pace=""
  left_s=$(duration "$left")
  if [[ -n $out ]] && (( out > 0 && out < left )); then
    out_s=$(duration "$out")
    # Same rounded value for both reads as a contradiction: add the minutes.
    if [[ $out_s == "$left_s" ]] && (( left >= 86400 )); then
      left_s="${left_s} $(( left % 3600 / 60 ))m"; out_s="${out_s} $(( out % 3600 / 60 ))m"
    fi
  elif [[ -n $proj ]]; then
    pace=$(printf '%.0f' "$proj"); (( pace > 99 )) && pace=99  # 100 would mean "out", shown above
  fi
  printf ' %sreset%s %s%s%s' "$c_sec" "$rst" "$c_time" "$left_s" "$rst"
  if [[ -n $out ]] && (( out == 0 )); then printf '%s,%s %sfull%s' "$c_sec" "$rst" "$c_crit" "$rst"
  elif [[ -n $out_s ]]; then
    printf '%s,%s %sout %s%s %s(%s%%/h)%s' "$c_sec" "$rst" "$c_crit" "$out_s" "$rst" \
      "$c_sec" "$(rate "$per_hour")" "$rst"
  elif [[ -n $pace ]]; then
    printf '%s, ends%s %s%s%%%s %s(%s%%/h)%s' "$c_sec" "$rst" "$(level "$pace")" "$pace" "$rst" \
      "$c_sec" "$(rate "$per_hour")" "$rst"
  fi
}

# Context: 8-cell bar, percent, tokens used of the window.
if [[ -n $pct ]]; then
  p=$(printf '%.0f' "$pct")
  filled=$(( (p * 8 + 50) / 100 )); (( filled > 8 )) && filled=8
  bar=""; empty=""
  for ((i = 0; i < 8; i++)); do (( i < filled )) && bar+="█" || empty+="░"; done
  color=$(level "$p"); fill=$c_bar
  (( p >= 50 )) && fill=$color
  ctx="${fill}${bar}${rst}${c_empty}${empty}${rst} ${color}${p}%${rst}"
  [[ -n $used ]] && ctx+=" ${c_sec}$(short "$used")/$(short "$size")${rst}"
else
  ctx="${c_empty}░░░░░░░░${rst} ${c_sec}–${rst}"
fi

line="${c_label}ctx${rst} ${ctx}"
# 5h: sample every 2 min, fitted curve with a 1 h half-life (over a few hours the recent trend holds).
# Week: sample every 15 min, the pace now from the whole-percent steps with a 4 h half-life.
fh=$(limit 5h "$fh_pct" "$fh_reset" 18000 120 3600 5h project); [[ -n $fh ]] && line+="${sep}${fh}"
wk=$(limit wk "$wk_pct" "$wk_reset" 604800 900 14400 week step_pace); [[ -n $wk ]] && line+="${sep}${wk}"
line+="${sep}${c_label}${model}${rst}"
[[ -n $effort ]] && line+=" ${c_effort}${effort}${rst}"
# Session name on its own bold row, which Claude Code draws just above its footer (the permission mode
# indicator); cut to the terminal width, which Claude Code passes in COLUMNS.
if [[ -n $session ]]; then
  LC_ALL=${LANG:-en_US.UTF-8}  # count characters, not bytes, when cutting long names
  max=$(( ${COLUMNS:-80} - 2 )); (( max < 10 )) && max=10
  (( ${#session} > max )) && session="${session:0:max-1}…"
  line2="${c_val}${session}${rst}"
fi
if [[ $dir == "$HOME" ]]; then dir="~"; else dir=${dir##*/}; fi
[[ -n $dir ]] && line+="${sep}${c_sec}${dir}${rst}"

printf '%s' "$line"
[[ -n ${line2:-} ]] && printf '\n%s' "$line2"
