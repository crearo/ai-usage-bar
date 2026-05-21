#!/bin/zsh

# <xbar.title>Agent Usage</xbar.title>
# <xbar.version>v1.1.0</xbar.version>
# <xbar.author>local</xbar.author>
# <xbar.desc>Shows today's Claude/Codex usage in the macOS menu bar.</xbar.desc>
# <xbar.dependencies>ccusage,node</xbar.dependencies>
# <swiftbar.refreshOnOpen>true</swiftbar.refreshOnOpen>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

script_path="${0:A}"
plugin_dir="${0:A:h}"
config_file="$plugin_dir/.usage-counter.conf"
stderr_dir="${TMPDIR:-/tmp}/swiftbar-agent-usage"

mode="codex"
reset_hour="0"

read_config() {
  [[ -f "$config_file" ]] || return

  while IFS='=' read -r key value; do
    case "$key" in
      MODE) mode="$value" ;;
      RESET_HOUR) reset_hour="$value" ;;
    esac
  done < "$config_file"

  case "$mode" in
    claude|codex|both) ;;
    *) mode="codex" ;;
  esac

  if [[ "$reset_hour" != <-> ]] || (( reset_hour < 0 || reset_hour > 23 )); then
    reset_hour="0"
  fi
}

write_config() {
  {
    echo "MODE=$mode"
    echo "RESET_HOUR=$reset_hour"
  } > "$config_file"
}

read_config

case "$1" in
  set-mode)
    case "$2" in
      claude|codex|both)
        mode="$2"
        write_config
        ;;
    esac
    exit 0
    ;;
  set-reset-hour)
    if [[ "$2" == <-> ]] && (( $2 >= 0 && $2 <= 23 )); then
      reset_hour="$2"
      write_config
    fi
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

MODE="$mode" \
RESET_HOUR="$reset_hour" \
DISPLAY_DATE="$display_date" \
QUERY_DATE="$query_date" \
TIMEZONE_NAME="$timezone_name" \
SCRIPT_PATH="$script_path" \
CLAUDE_USAGE_JSON="$claude_json" \
CODEX_USAGE_JSON="$codex_json" \
/usr/bin/env node <<'NODE'
const mode = process.env.MODE || "codex";
const resetHour = Number.parseInt(process.env.RESET_HOUR || "0", 10);
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
  return `$${Math.round(value).toLocaleString("en-US")}`;
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
  console.log("Reset time");
  for (const hour of [0, 4, 8, 12]) {
    const label = `${String(hour).padStart(2, "0")}:00`;
    console.log(`${selected(resetHour, hour)} ${label} | ${action("set-reset-hour", hour)}`);
  }

  console.log("---");
  console.log("Refresh | refresh=true");
  console.log(`Config: ${queryDate}`);
} catch (error) {
  console.log("Usage ? | color=#d14343 sfimage=exclamationmark.triangle");
  console.log("---");
  console.log(`Could not parse ccusage JSON: ${error.message}`);
}
NODE
