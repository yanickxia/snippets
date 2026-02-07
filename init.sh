#!/bin/sh
set -e
command_exists() { command -v "$1" >/dev/null 2>&1; }
die() { echo "Error: $*" >&2; exit 1; }
usage() {
	cat <<'EOF'
用法:
  init.sh [-h]
  init.sh                       交互式初始化 Docker、oh-my-zsh，并获取 Bitwarden SSH
  init.sh -n -p <主密码> -i <名称或ID> [-o <路径>] [-k p|P|a]

说明:
  - 平台: macOS 优先
  - Docker: 安装并启动 Docker Desktop
  - oh-my-zsh: 安装并切换默认 shell 为 zsh
  - Bitwarden SSH: 默认保存类型 a，默认路径 ~/.ssh/id_rsa

参数:
  -h            显示帮助
  -n            非交互模式
  -p <主密码>   Bitwarden 主密码
  -i <名称或ID> Bitwarden 条目名称或 ID
  -o <路径>     输出文件路径, 默认 ~/.ssh/id_rsa
  -k p|P|a      保存类型: p 私钥, P 公钥, a 全部; 默认 a
EOF
}
expand_path() {
	case "$1" in
		"~") printf '%s' "$HOME" ;;
		~/*) printf '%s%s' "$HOME" "${1#\~}" ;;
		*) printf '%s' "$1" ;;
	esac
}
non_interactive=0
master_password=""
item_cli=""
output_cli=""
kind_cli=""
while getopts "hni:p:o:k:" opt; do
	case "$opt" in
		h) usage; exit 0 ;;
		n) non_interactive=1 ;;
		p) master_password="$OPTARG" ;;
		i) item_cli="$OPTARG" ;;
		o) output_cli="$OPTARG" ;;
		k) kind_cli="$OPTARG" ;;
	esac
done
script_dir="$(cd "$(dirname "$0")" && pwd)"
os="$(uname -s)"
if [ "$os" = "Darwin" ]; then
	if ! command_exists docker; then
		if command_exists brew; then
			brew install --cask docker || true
		fi
	fi
	open -a Docker 2>/dev/null || true
	i=0
	while [ $i -lt 30 ]; do
		if docker info >/dev/null 2>&1; then
			break
		fi
		sleep 2
		i=$((i+1))
	done
fi
if ! command_exists zsh; then
	if command_exists brew; then
		brew install zsh || true
	fi
fi
if [ -x "$(command -v zsh)" ]; then
	if [ "$SHELL" != "$(command -v zsh)" ]; then
		chsh -s "$(command -v zsh)" || true
	fi
fi
if [ ! -d "$HOME/.oh-my-zsh" ]; then
	RUNZSH=no CHSH=yes KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
zsh -ic "exit" || true
if ! command_exists bw; then
	sh "$script_dir/bitwarden/install-bw.sh"
fi
ssh_script="$script_dir/bitwarden/get-ssh-from-bitwarden.sh"
if [ "$non_interactive" -eq 1 ]; then
	[ -n "$master_password" ] || die "缺少参数 -p"
	[ -n "$item_cli" ] || die "缺少参数 -i"
	args="-n -p" 
	set -- "$ssh_script" -n -p "$master_password" -i "$item_cli"
	if [ -n "$output_cli" ]; then
		set -- "$@" -o "$(expand_path "$output_cli")"
	fi
	if [ -n "$kind_cli" ]; then
		set -- "$@" -k "$kind_cli"
	fi
	sh "$@"
else
	sh "$ssh_script"
fi
