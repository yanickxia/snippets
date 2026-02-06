#!/bin/sh
set -e

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

if command_exists bw; then
	echo "bw already installed: $(bw --version)"
	exit 0
fi

if ! command_exists curl; then
	echo "Error: curl is required." >&2
	exit 1
fi

if ! command_exists unzip; then
	echo "Error: unzip is required." >&2
	exit 1
fi

case "$(uname -s)" in
	Linux)
		platform="linux"
		;;
	Darwin)
		platform="macos"
		;;
	*)
		echo "Error: unsupported OS. Only Linux and macOS are supported." >&2
		exit 1
		;;
esac

download_url="https://vault.bitwarden.com/download/?app=cli&platform=${platform}"
tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t bwcli)"

cleanup() {
	rm -rf "$tmp_dir"
}
trap cleanup EXIT

zip_path="$tmp_dir/bw.zip"
curl -fsSL "$download_url" -o "$zip_path"
unzip -q "$zip_path" -d "$tmp_dir"

if [ ! -f "$tmp_dir/bw" ]; then
	echo "Error: download did not contain bw binary." >&2
	exit 1
fi

install_dir="${INSTALL_DIR:-}"
if [ -z "$install_dir" ]; then
	if [ "$(id -u)" -eq 0 ]; then
		install_dir="/usr/local/bin"
	else
		install_dir="$HOME/.local/bin"
		mkdir -p "$install_dir"
	fi
fi

if [ ! -w "$install_dir" ]; then
	echo "Error: $install_dir is not writable. Use sudo or set INSTALL_DIR." >&2
	exit 1
fi

if command_exists install; then
	install -m 0755 "$tmp_dir/bw" "$install_dir/bw"
else
	cp "$tmp_dir/bw" "$install_dir/bw"
	chmod 0755 "$install_dir/bw"
fi

echo "Installed bw to $install_dir/bw"
"$install_dir/bw" --version
