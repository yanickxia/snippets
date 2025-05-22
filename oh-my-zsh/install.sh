#!/bin/bash

location() {
    # 确保 curl 存在
    if ! command -v curl >/dev/null 2>&1; then
        echo "错误：curl 未安装" >&2
        exit 1
    fi

    response=$(curl -s https://myip.ipip.net/json)

    if echo "$response" | grep -q '"中国"'; then
        return 0
    else
        return 1
    fi
}

install() {
    if location; then
        echo "当前为国内环境，安装清华源 oh-my-zsh"
        git clone https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git
        cd ohmyzsh/tools || exit
        REMOTE=https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git sh install.sh --unattended
        cd ../../ && rm -rf ohmyzsh
    else
        echo "当前为国外环境，开始安装 oh-my-zsh"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
}

install
