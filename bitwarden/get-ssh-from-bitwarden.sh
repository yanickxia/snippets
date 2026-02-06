#!/bin/sh
set -e

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

die() {
	echo "Error: $*" >&2
	exit 1
}

usage() {
	cat <<'EOF'
Usage:
  get-ssh-from-bitwarden.sh -i <item-name-or-id> -a <attachment-name> -o <output-path> [-f]

Notes:
  - Store the SSH key as an attachment in a Bitwarden item.
  - You must be logged in with "bw login" before running this script.
  - If the vault is locked, the script will prompt to unlock.
EOF
}

item=""
attachment=""
output=""
force=0

while getopts "i:a:o:fh" opt; do
	case "$opt" in
		i) item="$OPTARG" ;;
		a) attachment="$OPTARG" ;;
		o) output="$OPTARG" ;;
		f) force=1 ;;
		h) usage; exit 0 ;;
		*) usage; exit 1 ;;
	esac
done

if [ -z "$item" ] || [ -z "$attachment" ] || [ -z "$output" ]; then
	usage
	exit 1
fi

command_exists bw || die "bw CLI not found. Install it first."

status="$(bw status 2>/dev/null | tr -d ' \n')"
case "$status" in
	*'"status":"unauthenticated"'*)
		die "bw is not logged in. Run: bw login"
		;;
	*'"status":"locked"'*)
		if [ -z "${BW_SESSION:-}" ]; then
			BW_SESSION="$(bw unlock --raw)"
			[ -n "$BW_SESSION" ] || die "failed to unlock vault"
			export BW_SESSION
		fi
		;;
	*'"status":"unlocked"'*)
		;;
	*)
		echo "Warning: unable to determine bw status." >&2
		;;
esac

if command_exists python3; then
	py_cmd="python3"
elif command_exists python; then
	py_cmd="python"
else
	die "python is required to parse bw output"
fi

item_json="$(bw get item "$item")" || die "item not found: $item"
item_id="$(printf '%s' "$item_json" | "$py_cmd" -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
[ -n "$item_id" ] || die "unable to resolve item id"

output_dir="$(dirname "$output")"
mkdir -p "$output_dir"

if [ -e "$output" ] && [ "$force" -ne 1 ]; then
	die "output exists: $output (use -f to overwrite)"
fi

umask 077
bw get attachment "$attachment" --itemid "$item_id" --output "$output"

case "$output" in
	*.pub) chmod 0644 "$output" ;;
	*) chmod 0600 "$output" ;;
esac

echo "Saved attachment to $output"
