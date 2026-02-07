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
case "$os" in
	Darwin)
		echo "检测到平台: macOS"
		if ! command_exists docker; then
			echo "未检测到 docker 命令，尝试安装 Docker Desktop"
			if command_exists brew; then
				brew install --cask docker || true
			else
				echo "未检测到 Homebrew，跳过自动安装 Docker Desktop"
			fi
		else
			echo "已检测到 docker: $(docker --version 2>/dev/null || echo 未知版本)"
		fi
		echo "启动 Docker Desktop (如果已安装)"
		open -a Docker 2>/dev/null || true
		i=0
		echo "等待 Docker 就绪..."
		while [ $i -lt 30 ]; do
			if docker info >/dev/null 2>&1; then
				echo "Docker 已就绪"
				break
			fi
			sleep 2
			i=$((i+1))
		done
		;;
	Linux)
		echo "检测到平台: Linux"
		if ! command_exists docker; then
			if [ -f "$script_dir/docker/get-docker.sh" ]; then
				echo "执行本地 get-docker.sh 安装 Docker"
				sh "$script_dir/docker/get-docker.sh"
			else
				echo "未找到 get-docker.sh，跳过自动安装"
			fi
		else
			echo "已检测到 docker: $(docker --version 2>/dev/null || echo 未知版本)"
		fi
		i=0
		echo "等待 Docker 就绪..."
		while [ $i -lt 30 ]; do
			if docker info >/dev/null 2>&1; then
				echo "Docker 已就绪"
				break
			fi
			sleep 2
			i=$((i+1))
		done
		;;
	*)
		echo "当前平台: $os"
		;;
esac

if ! command_exists zsh; then
	echo "未检测到 zsh，尝试安装"
	if command_exists brew; then
		brew install zsh || true
	else
		echo "未检测到 Homebrew，跳过自动安装 zsh"
	fi
else
	echo "已检测到 zsh: $(command -v zsh)"
fi

if [ -x "$(command -v zsh)" ]; then
	if [ "$SHELL" != "$(command -v zsh)" ]; then
		echo "切换默认 shell 为 zsh"
		chsh -s "$(command -v zsh)" || true
	else
		echo "默认 shell 已是 zsh: $SHELL"
	fi
fi

if [ ! -d "$HOME/.oh-my-zsh" ]; then
	echo "未检测到 oh-my-zsh，开始安装"
	RUNZSH=no CHSH=yes KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
	echo "oh-my-zsh 安装完成"
else
	echo "oh-my-zsh 已安装: $HOME/.oh-my-zsh"
fi

zsh -ic "exit" || true

if ! command_exists bw; then
	echo "未检测到 bw CLI，开始安装"
	sh "$script_dir/bitwarden/install-bw.sh"
else
	echo "bw CLI 已安装: $(bw --version 2>/dev/null || echo 未知版本)"
fi

ssh_script="$script_dir/bitwarden/get-ssh-from-bitwarden.sh"
if [ "$non_interactive" -eq 1 ]; then
	[ -n "$master_password" ] || die "缺少参数 -p"
	[ -n "$item_cli" ] || die "缺少参数 -i"
	echo "以非交互模式获取 SSH 密钥: item=$item_cli kind=${kind_cli:-a} output=${output_cli:-~/.ssh/id_rsa}"
	set -- "$ssh_script" -n -p "$master_password" -i "$item_cli"
	if [ -n "$output_cli" ]; then
		set -- "$@" -o "$(expand_path "$output_cli")"
	fi
	if [ -n "$kind_cli" ]; then
		set -- "$@" -k "$kind_cli"
	fi
	sh "$@"
else
	echo "以交互模式运行 SSH 获取脚本"
	sh "$ssh_script"
fi
