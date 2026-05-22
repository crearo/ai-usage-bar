#!/bin/zsh

# <xbar.title>Agent Usage</xbar.title>
# <xbar.version>v1.3.0</xbar.version>
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
payload_file="$stderr_dir/payload.json"

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
  rm -f "$cache_output_file" "$cache_meta_file" "$payload_file"
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

ccusage_available="true"
if command -v ccusage >/dev/null 2>&1; then
  ccusage_cmd=(ccusage)
elif command -v npx >/dev/null 2>&1; then
  ccusage_cmd=(npx --yes --prefer-offline ccusage@latest)
elif command -v bunx >/dev/null 2>&1; then
  ccusage_cmd=(bunx ccusage@latest)
else
  ccusage_available="false"
  ccusage_cmd=()
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

collect_report_files() {
  local source="$1"
  local stdout_file="$stderr_dir/$source.out"
  local stderr_file="$stderr_dir/$source.err"
  local command_text="${ccusage_cmd[*]} $source daily --json --since $query_date --until $query_date --offline ${timezone_args[*]}"

  if [[ "$ccusage_available" != "true" ]]; then
    printf "%s\n" "Missing dependency: install ccusage, Node.js/npm, or Bun." >"$stderr_file"
    printf '%s\t%s\t%s\t%s\t%s\n' "$source" "error" "ccusage unavailable" "$stdout_file" "$stderr_file"
    return
  fi

  "${ccusage_cmd[@]}" "$source" daily --json --since "$query_date" --until "$query_date" --offline "${timezone_args[@]}" >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?

  local stderr_text=""
  local stdout_text=""
  [[ -s "$stderr_file" ]] && stderr_text="$(cat "$stderr_file")"
  [[ -s "$stdout_file" ]] && stdout_text="$(cat "$stdout_file")"

  if (( exit_code != 0 )); then
    if printf '%s\n%s' "$stderr_text" "$stdout_text" | grep -q "No valid .* data directories found"; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$source" "missing_data" "$command_text" "$stdout_file" "$stderr_file"
    else
      printf '%s\t%s\t%s\t%s\t%s\n' "$source" "error" "$command_text" "$stdout_file" "$stderr_file"
    fi
    return
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$source" "ok" "$command_text" "$stdout_file" "$stderr_file"
}

report_specs=()
case "$mode" in
  claude)
    report_specs+=("$(collect_report_files claude)")
    ;;
  codex)
    report_specs+=("$(collect_report_files codex)")
    ;;
  both)
    report_specs+=("$(collect_report_files claude)")
    report_specs+=("$(collect_report_files codex)")
    ;;
esac

REPORT_SPECS="${(F)report_specs}" \
PAYLOAD_FILE="$payload_file" \
MODE="$mode" \
RESET_HOUR="$reset_hour" \
REFRESH_SECONDS="$refresh_seconds" \
DISPLAY_DATE="$display_date" \
QUERY_DATE="$query_date" \
TIMEZONE_NAME="$timezone_name" \
SCRIPT_PATH="$script_path" \
/usr/bin/env node <<'NODE_PAYLOAD'
const fs = require("fs");

const payload = {
  mode: process.env.MODE || "both",
  resetHour: Number.parseInt(process.env.RESET_HOUR || "0", 10),
  refreshSeconds: Number.parseInt(process.env.REFRESH_SECONDS || "60", 10),
  displayDate: process.env.DISPLAY_DATE || "",
  queryDate: process.env.QUERY_DATE || "",
  timezoneName: process.env.TIMEZONE_NAME || "",
  scriptPath: process.env.SCRIPT_PATH || "",
  reports: [],
};

function readMaybe(path) {
  if (!path || !fs.existsSync(path)) return "";
  return fs.readFileSync(path, "utf8");
}

for (const spec of process.env.REPORT_SPECS ? process.env.REPORT_SPECS.split("\n") : []) {
  if (!spec.trim()) continue;
  const [source, status, command, stdoutPath, stderrPath] = spec.split("\t");
  const stdout = readMaybe(stdoutPath);
  const stderr = readMaybe(stderrPath);
  payload.reports.push({ source, status, command, stdout, stderr });
}

fs.writeFileSync(process.env.PAYLOAD_FILE, JSON.stringify(payload));
NODE_PAYLOAD

REPORT_SPECS="${(F)report_specs}" PAYLOAD_FILE="$payload_file" /usr/bin/env node <<'NODE_RENDER' > "$cache_output_file"
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.env.PAYLOAD_FILE, "utf8"));

const mode = payload.mode || "both";
const resetHour = Number.isFinite(payload.resetHour) ? payload.resetHour : 0;
const refreshSeconds = Number.isFinite(payload.refreshSeconds) ? payload.refreshSeconds : 60;
const displayDate = payload.displayDate || "";
const queryDate = payload.queryDate || "";
const timezoneName = payload.timezoneName || "system timezone";
const scriptPath = payload.scriptPath || "";

function numberValue(...values) {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) return value;
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
    return { parseError: `${label}: ${error.message}` };
  }
}

function modelNames(row) {
  if (Array.isArray(row.models)) return row.models;
  if (row.models && typeof row.models === "object") return Object.keys(row.models);
  if (Array.isArray(row.modelsUsed)) return row.modelsUsed;
  return [];
}

function emptyUsage(label, status = "missing_data", error = "") {
  return {
    label,
    status,
    error,
    input: 0,
    output: 0,
    cacheCreate: 0,
    cacheRead: 0,
    reasoning: 0,
    total: 0,
    cost: 0,
    models: [],
  };
}

function normalizeReport(report) {
  const label = report.source === "claude" ? "Claude" : report.source === "codex" ? "Codex" : report.source;

  if (report.status === "missing_data") return emptyUsage(label, "missing_data");
  if (report.status === "error") {
    const detail = (report.stderr || report.stdout || "Unknown error").trim().split("\n").slice(0, 3).join(" ");
    return emptyUsage(label, "error", detail || "Unknown error");
  }

  const parsed = parseJson(report.stdout, label);
  if (parsed.parseError) return emptyUsage(label, "error", parsed.parseError);

  const rows = Array.isArray(parsed.daily) ? parsed.daily : Array.isArray(parsed.data) ? parsed.data : [];
  const summary = parsed.totals || parsed.summary || {};
  const row = rows.find((item) => item.date === displayDate) || rows[rows.length - 1] || {};

  const input = numberValue(row.inputTokens, summary.inputTokens, summary.totalInputTokens);
  const output = numberValue(row.outputTokens, summary.outputTokens, summary.totalOutputTokens);
  const cacheCreate = numberValue(row.cacheCreationTokens, summary.cacheCreationTokens, summary.totalCacheCreationTokens);
  const cacheRead = numberValue(
    row.cacheReadTokens,
    row.cachedInputTokens,
    summary.cacheReadTokens,
    summary.cachedInputTokens,
    summary.totalCacheReadTokens,
    summary.totalCachedInputTokens,
  );
  const reasoning = numberValue(row.reasoningOutputTokens, summary.reasoningOutputTokens, summary.totalReasoningOutputTokens);
  const total = numberValue(row.totalTokens, summary.totalTokens, input + output + cacheCreate + cacheRead + reasoning);
  const cost = numberValue(row.costUSD, row.totalCost, summary.costUSD, summary.totalCost, summary.totalCostUSD);

  return {
    label,
    status: "ok",
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
  const total = { input: 0, output: 0, cacheCreate: 0, cacheRead: 0, reasoning: 0, total: 0, cost: 0, models: new Set() };
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

const reports = payload.reports.map(normalizeReport);
const total = addReports(reports);
const models = [...total.models].length > 0 ? [...total.models].join(", ") : "No model data";
const resetLabel = `${String(resetHour).padStart(2, "0")}:00`;
const hasErrors = reports.some((report) => report.status === "error");

console.log(`${modeLabel()} ${money(total.cost)} ${compactNumber(total.total)}${hasErrors ? " !" : ""}`);
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
    if (report.status === "missing_data") {
      console.log(`${report.label}: no data`);
    } else if (report.status === "error") {
      console.log(`${report.label}: error`);
    } else {
      console.log(`${report.label}: ${money(report.cost)} ${compactNumber(report.total)}`);
    }
  }
}

const errorReports = reports.filter((report) => report.status === "error");
if (errorReports.length > 0) {
  console.log("---");
  console.log("Errors");
  for (const report of errorReports) {
    console.log(`${report.label}: ${report.error || "Unknown error"}`);
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
NODE_RENDER
node_exit=$?

cat "$cache_output_file"

if (( node_exit == 0 )); then
  {
    echo "CACHE_KEY=$cache_key"
    echo "LAST_RUN=$now"
  } > "$cache_meta_file"
else
  rm -f "$cache_meta_file"
fi
