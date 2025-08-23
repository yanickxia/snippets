#!/bin/bash

# 预定义 IS_CHINA，默认为 1（国外环境）
IS_CHINA='n'

# 检查是否为 Ubuntu 系统
check_ubuntu() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "ubuntu" ]; then
            echo "错误：此脚本仅支持 Ubuntu 系统，当前系统为 $ID" >&2
            exit 1
        fi
        echo "检测到 Ubuntu 系统：$VERSION"
    else
        echo "错误：无法检测系统类型，缺少 /etc/os-release" >&2
        exit 1
    fi
}


# 检查并更新 location 的结果
check_location() {
    # 确保 curl 存在
    if ! command -v curl >/dev/null 2>&1; then
        echo "错误：curl 未安装，安装 curl" >&2
        exit 1
    fi

    # 获取 API 响应
    response=$(curl -s https://myip.ipip.net/json)

    # 检查是否包含 "中国"，并更新 IS_CHINA
    if echo "$response" | grep -q '"中国"'; then
        IS_CHINA=0
    else
        IS_CHINA=1
    fi
}

# base install
install_base() {
    apt update
    apt install -y git curl
}

# install oh my zsh
install_zsh() {
    apt install -y git zsh
    if [ "$IS_CHINA" -eq 0 ]; then
        echo "当前为国内环境，安装清华源 oh-my-zsh"
        git clone https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git
        cd ohmyzsh/tools || exit
        REMOTE=https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git sh install.sh --unattended
        cd ../../ && rm -rf ohmyzsh
        chsh -s /usr/bin/zsh
    else
        echo "当前为国外环境，开始安装 oh-my-zsh"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
}


# replace mirrors
replace_mirror() {
    if [ "$IS_CHINA" -eq 0 ]; then
        echo "当前为国内环境，替换国内源"
        sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list
        sed -i 's/security.ubuntu.com/mirrors.ustc.edu.cn/g' /etc/apt/sources.list
    fi
}


# 通用函数：检查命令是否安装并输出版本
check_command() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        echo "$cmd 已成功安装，版本：$($cmd --version | head -n 1)"
    else
        echo "$cmd 安装失败，请检查错误信息！"
        exit 1
    fi
}

install_vim() {
    read -p "安装 vim？ [y/n]: " install
    if [ "$install" = "y" ]; then
        echo "正在安装 vim..."
        apt install -y vim
        if command -v vim &>/dev/null; then
            echo "vim 已成功安装，版本：$(vim --version | head -n 1)"
        else
            echo "vim 安装失败，请检查错误信息！"
        fi
    fi
}

install_uv() {
    read -p "安装 python && uv？ [y/n]: " install
    if [ "$install" = "y" ]; then
        echo "正在安装 uv..."
        # With pip.
        apt install -y python3 python3-pip
        if [ "$IS_CHINA" -eq 0 ]; then
            pip config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple
        fi
        pip install uv
    fi
}

install_docker() {
    read -p "安装 docker？ [y/n]: " install
    if [ "$install" = "y" ]; then
        if [ "$IS_CHINA" -eq 0 ]; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            DOWNLOAD_URL=https://mirrors.ustc.edu.cn/docker-ce sh get-docker.sh
        else
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
        fi
    fi
}


# 允许用户交互式覆盖 IS_CHINA
read -p "是否国内环境？ [y/n]: " user_input
if [ "$user_input" = "y" ]; then
    IS_CHINA=0
elif [ "$user_input" = "n" ]; then
    IS_CHINA=1
fi

# check_ubuntu

# 更新镜像源
replace_mirror

# 安装基础镜像
install_base

# 调用 install 函数
install_zsh


# 交互式询问是否安装其他常用工具
echo "是否需要安装其他常用工具？（输入 y/n）"

install_vim
install_uv

echo "初始化完成！"