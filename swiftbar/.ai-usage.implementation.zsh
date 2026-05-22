#!/bin/zsh

# <xbar.title>Agent Usage</xbar.title>
# <xbar.version>v1.2.0</xbar.version>
# <xbar.author>local</xbar.author>
# <xbar.desc>Shows today's Claude/Codex usage in the macOS menu bar.</xbar.desc>
# <xbar.dependencies>ccusage,node</xbar.dependencies>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

# Hidden implementation file: SwiftBar should expose only ai-usage.15s.sh as the menu item.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

script_path="${USAGE_COUNTER_WRAPPER_PATH:-${0:A}}"
plugin_dir="${0:A:h}"
config_file="$plugin_dir/.usage-counter.conf"
stderr_dir="${TMPDIR:-/tmp}/swiftbar-agent-usage"
cache_output_file="$stderr_dir/menu.out"
cache_meta_file="$stderr_dir/menu.meta"

mode="both"
reset_hour="0"
refresh_seconds="60"

read_config() {
  [[ -f "$config_file" ]] || return

  while IFS='=' read -r key value; do
    case "$key" in
      MODE) mode="$value" ;;
      RESET_HOUR) reset_hour="$value" ;;
      REFRESH_SECONDS) refresh_seconds="$value" ;;
    esac
  done < "$config_file"

  case "$mode" in
    claude|codex|both) ;;
    *) mode="both" ;;
  esac

  if [[ "$reset_hour" != <-> ]] || (( reset_hour < 0 || reset_hour > 23 )); then
    reset_hour="0"
  fi

  case "$refresh_seconds" in
    15|30|60|300) ;;
    *) refresh_seconds="60" ;;
  esac
}

write_config() {
  {
    echo "MODE=$mode"
    echo "RESET_HOUR=$reset_hour"
    echo "REFRESH_SECONDS=$refresh_seconds"
  } > "$config_file"
}

clear_cache() {
  rm -f "$cache_output_file" "$cache_meta_file"
}

read_config

case "$1" in
  set-mode)
    case "$2" in
      claude|codex|both)
        mode="$2"
        write_config
        clear_cache
        ;;
    esac
    exit 0
    ;;
  set-reset-hour)
    if [[ "$2" == <-> ]] && (( $2 >= 0 && $2 <= 23 )); then
      reset_hour="$2"
      write_config
      clear_cache
    fi
    exit 0
    ;;
  set-refresh-seconds)
    case "$2" in
      15|30|60|300)
        refresh_seconds="$2"
        write_config
        clear_cache
        ;;
    esac
    exit 0
    ;;
  force-refresh)
    clear_cache
    exit 0
    ;;
esac

mkdir -p "$stderr_dir"

if command -v ccusage >/dev/null 2>&1; then
  ccusage_cmd=(ccusage)
elif command -v npx >/dev/null 2>&1; then
  ccusage_cmd=(npx --yes --prefer-offline ccusage@latest)
elif command -v bunx >/dev/null 2>&1; then
  ccusage_cmd=(bunx ccusage@latest)
else
  echo "Usage ? | color=#d14343 sfimage=exclamationmark.triangle"
  echo "---"
  echo "Missing dependency: install ccusage, Node.js/npm, or Bun."
  exit 0
fi

display_date="$(date -v-"${reset_hour}"H +%F 2>/dev/null || date +%F)"
query_date="$(date -v-"${reset_hour}"H +%Y%m%d 2>/dev/null || date +%Y%m%d)"
timezone_name=""
timezone_args=()

if (( reset_hour > 0 )); then
  offset_raw="$(date +%z)"
  offset_sign="${offset_raw[1,1]}"
  offset_hour="${offset_raw[2,3]}"
  local_offset=$((10#$offset_hour))
  if [[ "$offset_sign" == "-" ]]; then
    local_offset=$((-local_offset))
  fi

  shifted_offset=$((local_offset - reset_hour))
  if (( shifted_offset == 0 )); then
    timezone_name="UTC"
  elif (( shifted_offset > 0 )); then
    timezone_name="Etc/GMT-${shifted_offset}"
  else
    timezone_name="Etc/GMT+$((-shifted_offset))"
  fi
  timezone_args=(--timezone "$timezone_name")
fi

cache_key="$mode|$reset_hour|$refresh_seconds|$display_date|$query_date|$timezone_name"
cache_key_saved=""
cache_last_run="0"
now="$(date +%s)"

if [[ -f "$cache_meta_file" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      CACHE_KEY) cache_key_saved="$value" ;;
      LAST_RUN) cache_last_run="$value" ;;
    esac
  done < "$cache_meta_file"
fi

if [[ -s "$cache_output_file" && "$cache_key_saved" == "$cache_key" && "$cache_last_run" == <-> ]]; then
  if (( now - cache_last_run < refresh_seconds )); then
    cat "$cache_output_file"
    exit 0
  fi
fi

run_report() {
  local source="$1"
  local stderr_file="$stderr_dir/$source.err"
  local output

  output="$("${ccusage_cmd[@]}" "$source" daily --json --since "$query_date" --until "$query_date" --offline "${timezone_args[@]}" 2>"$stderr_file")"
  local exit_code=$?

  if (( exit_code != 0 )); then
    echo "Usage ? | color=#d14343 sfimage=exclamationmark.triangle"
    echo "---"
    echo "Command failed:"
    echo "${ccusage_cmd[*]} $source daily --json --since $query_date --until $query_date --offline ${timezone_args[*]}"
    echo "---"
    if [[ -s "$stderr_file" ]]; then
      tail -n 20 "$stderr_file"
    else
      echo "$output"
    fi
    exit 0
  fi

  printf "%s" "$output"
}

claude_json="{}"
codex_json="{}"

case "$mode" in
  claude)
    claude_json="$(run_report claude)"
    ;;
  codex)
    codex_json="$(run_report codex)"
    ;;
  both)
    claude_json="$(run_report claude)"
    codex_json="$(run_report codex)"
    ;;
esac

menu_output="$(MODE="$mode" \
RESET_HOUR="$reset_hour" \
REFRESH_SECONDS="$refresh_seconds" \
DISPLAY_DATE="$display_date" \
QUERY_DATE="$query_date" \
TIMEZONE_NAME="$timezone_name" \
SCRIPT_PATH="$script_path" \
CLAUDE_USAGE_JSON="$claude_json" \
CODEX_USAGE_JSON="$codex_json" \
/usr/bin/env node <<'NODE'
const mode = process.env.MODE || "both";
const resetHour = Number.parseInt(process.env.RESET_HOUR || "0", 10);
const refreshSeconds = Number.parseInt(process.env.REFRESH_SECONDS || "60", 10);
const displayDate = process.env.DISPLAY_DATE || "";
const queryDate = process.env.QUERY_DATE || "";
const timezoneName = process.env.TIMEZONE_NAME || "system timezone";
const scriptPath = process.env.SCRIPT_PATH || "";

function numberValue(...values) {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
  }
  return 0;
}

function compactNumber(value) {
  const abs = Math.abs(value);
  if (abs >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(1)}B`;
  if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `${(value / 1_000).toFixed(1)}K`;
  return String(Math.round(value));
}

function fullNumber(value) {
  return Math.round(value).toLocaleString("en-US");
}

function money(value) {
  const rounded = Math.round(value);
  return `$${Object.is(rounded, -0) ? 0 : rounded.toLocaleString("en-US")}`;
}

function parseJson(raw, label) {
  try {
    return JSON.parse((raw || "{}").trim() || "{}");
  } catch (error) {
    throw new Error(`${label}: ${error.message}`);
  }
}

function modelNames(row) {
  if (Array.isArray(row.models)) return row.models;
  if (row.models && typeof row.models === "object") return Object.keys(row.models);
  if (Array.isArray(row.modelsUsed)) return row.modelsUsed;
  return [];
}

function normalizeReport(label, raw) {
  const report = parseJson(raw, label);
  const rows = Array.isArray(report.daily) ? report.daily : Array.isArray(report.data) ? report.data : [];
  const summary = report.totals || report.summary || {};
  const row = rows.find((item) => item.date === displayDate) || rows[rows.length - 1] || {};

  const input = numberValue(row.inputTokens, summary.inputTokens, summary.totalInputTokens);
  const output = numberValue(row.outputTokens, summary.outputTokens, summary.totalOutputTokens);
  const cacheCreate = numberValue(
    row.cacheCreationTokens,
    summary.cacheCreationTokens,
    summary.totalCacheCreationTokens,
  );
  const cacheRead = numberValue(
    row.cacheReadTokens,
    row.cachedInputTokens,
    summary.cacheReadTokens,
    summary.cachedInputTokens,
    summary.totalCacheReadTokens,
    summary.totalCachedInputTokens,
  );
  const reasoning = numberValue(
    row.reasoningOutputTokens,
    summary.reasoningOutputTokens,
    summary.totalReasoningOutputTokens,
  );
  const total = numberValue(
    row.totalTokens,
    summary.totalTokens,
    input + output + cacheCreate + cacheRead + reasoning,
  );
  const cost = numberValue(row.costUSD, row.totalCost, summary.costUSD, summary.totalCost, summary.totalCostUSD);

  return {
    label,
    input,
    output,
    cacheCreate,
    cacheRead,
    reasoning,
    total,
    cost,
    models: modelNames(row),
  };
}

function addReports(reports) {
  const total = {
    input: 0,
    output: 0,
    cacheCreate: 0,
    cacheRead: 0,
    reasoning: 0,
    total: 0,
    cost: 0,
    models: new Set(),
  };

  for (const report of reports) {
    total.input += report.input;
    total.output += report.output;
    total.cacheCreate += report.cacheCreate;
    total.cacheRead += report.cacheRead;
    total.reasoning += report.reasoning;
    total.total += report.total;
    total.cost += report.cost;
    for (const model of report.models) total.models.add(model);
  }

  return total;
}

function modeLabel(value = mode) {
  if (value === "claude") return "Claude";
  if (value === "both") return "AI";
  return "Codex";
}

function selected(current, value) {
  return current === value ? "[x]" : "[ ]";
}

function refreshLabel(seconds) {
  return `${seconds}s`;
}

function action(command, value) {
  return `bash=${scriptPath} param1=${command} param2=${value} terminal=false refresh=true`;
}

try {
  const reports = [];
  if (mode === "claude" || mode === "both") {
    reports.push(normalizeReport("Claude", process.env.CLAUDE_USAGE_JSON));
  }
  if (mode === "codex" || mode === "both") {
    reports.push(normalizeReport("Codex", process.env.CODEX_USAGE_JSON));
  }

  const total = addReports(reports);
  const models = [...total.models].length > 0 ? [...total.models].join(", ") : "No model data";
  const resetLabel = `${String(resetHour).padStart(2, "0")}:00`;

  console.log(`${modeLabel()} ${money(total.cost)} ${compactNumber(total.total)}`);
  console.log("---");
  console.log(`Mode: ${modeLabel()}`);
  console.log(`Refresh: ${refreshLabel(refreshSeconds)}`);
  console.log(`Usage day: ${displayDate}`);
  console.log(`Reset time: ${resetLabel}`);
  if (resetHour > 0) console.log(`Grouping timezone: ${timezoneName}`);
  console.log(`Cost: ${money(total.cost)}`);
  console.log(`Total tokens: ${fullNumber(total.total)}`);
  console.log(`Input: ${fullNumber(total.input)}`);
  console.log(`Output: ${fullNumber(total.output)}`);
  if (total.reasoning > 0) console.log(`Reasoning output: ${fullNumber(total.reasoning)}`);
  if (total.cacheCreate > 0) console.log(`Cache create: ${fullNumber(total.cacheCreate)}`);
  if (total.cacheRead > 0) console.log(`Cache read: ${fullNumber(total.cacheRead)}`);
  console.log(`Models: ${models}`);

  if (reports.length > 1) {
    console.log("---");
    for (const report of reports) {
      console.log(`${report.label}: ${money(report.cost)} ${compactNumber(report.total)}`);
    }
  }

  console.log("---");
  console.log("Mode");
  console.log(`${selected(mode, "codex")} Codex only | ${action("set-mode", "codex")}`);
  console.log(`${selected(mode, "claude")} Claude only | ${action("set-mode", "claude")}`);
  console.log(`${selected(mode, "both")} Claude + Codex | ${action("set-mode", "both")}`);

  console.log("---");
  console.log("Refresh interval");
  for (const seconds of [15, 30, 60, 300]) {
    console.log(`${selected(refreshSeconds, seconds)} ${refreshLabel(seconds)} | ${action("set-refresh-seconds", seconds)}`);
  }

  console.log("---");
  console.log("Reset time");
  for (const hour of [0, 4, 8, 12]) {
    const label = `${String(hour).padStart(2, "0")}:00`;
    console.log(`${selected(resetHour, hour)} ${label} | ${action("set-reset-hour", hour)}`);
  }

  console.log("---");
  console.log(`Refresh now | ${action("force-refresh", "1")}`);
  console.log("Made with <3 by crearo | href=https://github.com/crearo/ai-usage-bar");
  console.log(`Config: ${queryDate}`);
} catch (error) {
  console.log("Usage ? | color=#d14343 sfimage=exclamationmark.triangle");
  console.log("---");
  console.log(`Could not parse ccusage JSON: ${error.message}`);
}
NODE
)"
node_exit=$?

printf "%s\n" "$menu_output"

if (( node_exit == 0 )); then
  printf "%s\n" "$menu_output" > "$cache_output_file"
  {
    echo "CACHE_KEY=$cache_key"
    echo "LAST_RUN=$now"
  } > "$cache_meta_file"
fi
