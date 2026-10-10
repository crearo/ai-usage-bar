#!/bin/zsh

# Runs detached from the main plugin's render path (invoked via `nohup ... &`)
# so git network operations never block the menu bar from updating.
op="$1"
repo_root="$2"
stderr_dir="$3"
notify_result="$4"
update_meta_file="$stderr_dir/update.meta"

git_run_with_timeout() {
  local timeout_seconds="$1"; shift
  local ticks=$(( timeout_seconds * 2 ))
  ( GIT_TERMINAL_PROMPT=0 "$@" ) &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null && (( waited < ticks )); do
    sleep 0.5
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid"
}

notify() {
  [[ "$notify_result" == "true" ]] || return
  # Pass the message as an argv item (not string-interpolated into the
  # AppleScript source) so it's safe regardless of quotes/special characters.
  osascript -e 'on run argv
    display notification (item 1 of argv) with title "AI Usage"
  end run' "$1" >/dev/null 2>&1
}

[[ -d "$repo_root/.git" ]] || exit 0
mkdir -p "$stderr_dir"

if [[ "$op" == "pull" ]]; then
  git_run_with_timeout 20 git -C "$repo_root" pull --ff-only --quiet origin main
  if (( $? == 0 )); then
    notify "Updated to the latest version"
  else
    notify "Update failed — local changes may need to be resolved manually"
  fi
  rm -f "$update_meta_file"
  exit 0
fi

# op == check
behind_count="0"
if [[ -f "$update_meta_file" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in BEHIND_COUNT) behind_count="$value" ;; esac
  done < "$update_meta_file"
fi
[[ "$behind_count" == <-> ]] || behind_count="0"

git_run_with_timeout 8 git -C "$repo_root" fetch --quiet --no-tags origin main
if (( $? == 0 )); then
  fresh_count="$(git -C "$repo_root" rev-list --count HEAD..origin/main 2>/dev/null)"
  [[ "$fresh_count" == <-> ]] && behind_count="$fresh_count"
fi

tmp_meta="$update_meta_file.$$"
{
  echo "LAST_CHECK=$(date +%s)"
  echo "BEHIND_COUNT=$behind_count"
} > "$tmp_meta"
mv -f "$tmp_meta" "$update_meta_file"

if (( behind_count > 0 )); then
  plural="s"
  (( behind_count == 1 )) && plural=""
  notify "$behind_count commit$plural behind — click \"Update available\" in the menu to pull"
else
  notify "You're up to date"
fi
