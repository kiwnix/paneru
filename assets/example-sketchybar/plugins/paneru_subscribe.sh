#!/usr/bin/env bash
set -euo pipefail

lock_dir="${TMPDIR:-/tmp}/sketchybar-paneru-subscribe-${USER:-user}.lock"
pid_file="$lock_dir/pid"

export PATH="/etc/profiles/per-user/${USER:-egarcia}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

if ! mkdir "$lock_dir" 2>/dev/null; then
	if [[ -r "$pid_file" ]]; then
		IFS= read -r existing_pid <"$pid_file" || true
		if [[ "${existing_pid:-}" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
			exit 0
		fi
	fi
	rm -rf "$lock_dir"
	mkdir "$lock_dir"
fi

printf '%s\n' "$$" >"$pid_file"
trap 'rm -rf "$lock_dir"' EXIT

if ! command -v paneru >/dev/null 2>&1; then
	exit 0
fi

last_workspace_number=""
last_front_key=""
last_windows_key=""

trigger_workspace_changed() {
	local event_name="$1"
	local virtual_number="$2"
	local focused_app="$3"
	local focused_title="$4"
	local event_json="$5"

	[[ "$virtual_number" =~ ^[0-9]+$ ]] || return 0
	if [[ "$virtual_number" == "$last_workspace_number" ]]; then
		return 0
	fi

	last_workspace_number="$virtual_number"
	sketchybar --trigger paneru_workspace_changed \
		PANERU_EVENT="$event_name" \
		PANERU_VIRTUAL_WORKSPACE_NUMBER="$virtual_number" \
		INFO="$focused_app" \
		PANERU_WINDOW_TITLE="$focused_title" \
		PANERU_EVENT_JSON="$event_json" >/dev/null 2>&1 || true
}

trigger_front_app_changed() {
	local event_name="$1"
	local virtual_number="$2"
	local focused_app="$3"
	local focused_title="$4"
	local event_json="$5"
	local front_key="$focused_app|$focused_title"

	if [[ "$front_key" == "$last_front_key" ]]; then
		return 0
	fi

	last_front_key="$front_key"
	sketchybar --trigger paneru_front_app_changed \
		PANERU_EVENT="$event_name" \
		PANERU_VIRTUAL_WORKSPACE_NUMBER="$virtual_number" \
		INFO="$focused_app" \
		PANERU_WINDOW_TITLE="$focused_title" \
		PANERU_EVENT_JSON="$event_json" >/dev/null 2>&1 || true
}

trigger_windows_changed() {
	local event_name="$1"
	local virtual_number="$2"
	local event_json="$3"
	local windows_key="$event_name|$virtual_number|$event_json"

	if [[ "$windows_key" == "$last_windows_key" ]]; then
		return 0
	fi

	last_windows_key="$windows_key"
	sketchybar --trigger paneru_windows_changed \
		PANERU_EVENT="$event_name" \
		PANERU_VIRTUAL_WORKSPACE_NUMBER="$virtual_number" \
		PANERU_EVENT_JSON="$event_json" >/dev/null 2>&1 || true
}

trigger_from_event() {
	local event_json="$1"
	local event_name virtual_number focused_app focused_title

	[[ -n "$event_json" ]] || return 0
	if ! jq -e . >/dev/null 2>&1 <<<"$event_json"; then
		return 0
	fi

	event_name="$(jq -r '.event // empty' <<<"$event_json")"
	virtual_number="$(jq -r '.active.virtual_workspace_number // .virtual_workspace_number // empty' <<<"$event_json")"
	focused_app="$(jq -r '.active.focused_app_name // .focused_app_name // .active.focused_bundle_id // .bundle_id // empty' <<<"$event_json")"
	focused_title="$(jq -r '.active.focused_window_title // .title // empty' <<<"$event_json")"

	case "$event_name" in
	virtual_workspace_changed | display_changed)
		last_windows_key=""
		trigger_workspace_changed "$event_name" "$virtual_number" "$focused_app" "$focused_title" "$event_json"
		;;
	windows_changed)
		trigger_windows_changed "$event_name" "$virtual_number" "$event_json"
		;;
	window_focused | window_title_changed)
		last_windows_key=""
		trigger_front_app_changed "$event_name" "$virtual_number" "$focused_app" "$focused_title" "$event_json"

		if [[ "$event_name" == "window_focused" ]]; then
			trigger_workspace_changed "$event_name" "$virtual_number" "$focused_app" "$focused_title" "$event_json"
		fi
		;;
	esac
}

while true; do
	paneru subscribe --json 2>/dev/null | while IFS= read -r event_json; do
		trigger_from_event "$event_json"
	done || true

	if [[ "${PANERU_SUBSCRIBE_ONCE:-0}" == "1" ]]; then
		break
	fi

	sleep "${PANERU_SUBSCRIBE_RETRY_DELAY:-1}"
done
