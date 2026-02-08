#!/usr/bin/env zsh
set -euo pipefail

if [ -f "$HOME/.zshrc" ]; then
  source "$HOME/.zshrc"
fi

if ! command -v chezmoi >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "usr/local/bin"
fi

printf "请输入 dotfiles Git 仓库地址: "
read -r DOTFILES_GIT_URL
if [ -z "$DOTFILES_GIT_URL" ]; then
  echo "未提供仓库地址，退出。"
  exit 1
fi

chezmoi init --source "$DOTFILES_GIT_URL"
chezmoi apply
