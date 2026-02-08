#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  init/init.sh [-h] [-f] [-r <dotfiles-git-url>]
  -h    显示帮助
  -f    强制重新初始化（即使已安装/已初始化）
  -r    提供 dotfiles 仓库地址，非交互环境必需
EOF
}

force=0
repo_arg=""
while getopts "hfr:" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    f) force=1 ;;
    r) repo_arg="$OPTARG" ;;
  esac
done

if [ -f "$HOME/.zshrc" ]; then
  source "$HOME/.zshrc"
fi

if command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi 已安装: $(chezmoi --version)"
else
  install_dir="/usr/local/bin"
  if [ -w "$install_dir" ]; then
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "/usr/local/bin"
  else
    mkdir -p "$HOME/.local/bin"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
  fi
  echo "chezmoi 安装完成: $(chezmoi --version)"
fi

repo="${repo_arg:-${DOTFILES_GIT_URL:-}}"
if [ -z "$repo" ]; then
  if [ -r /dev/tty ]; then
    printf "请输入 dotfiles Git 仓库地址: " >/dev/tty
    read -r repo </dev/tty
  else
    echo "非交互环境且未提供仓库地址 (-r 或 DOTFILES_GIT_URL)，退出。"
    exit 1
  fi
fi

already_initialized=0
source_path="$(chezmoi source-path 2>/dev/null || true)"
if [ -n "$source_path" ] && [ -d "$source_path/.git" ]; then
  remote_url="$(git -C "$source_path" remote get-url origin 2>/dev/null || true)"
  if [ -n "$remote_url" ]; then
    already_initialized=1
    echo "检测到已初始化的 chezmoi 源: $source_path (origin: $remote_url)"
  fi
fi

if [ "$already_initialized" -eq 1 ] && [ "$force" -ne 1 ]; then
  echo "已初始化，跳过 init。使用 -f 可强制重新初始化。"
else
  if [ "$already_initialized" -eq 1 ] && [ "$force" -eq 1 ]; then
    echo "强制重新初始化 chezmoi"
    rm -rf "$source_path"
  fi
  echo "初始化 dotfiles 仓库: $repo"
  chezmoi init "$repo"
fi

echo "应用 dotfiles"
chezmoi apply
