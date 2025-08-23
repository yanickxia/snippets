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
    # 检查 ~/.oh-my-zsh 目录是否存在
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "oh-my-zsh 已经安装，跳过安装"
        return
    fi

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
    if command -v vim &>/dev/null; then
        echo "vim 已经安装，跳过安装"
        return
    fi

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
    if command -v uv &>/dev/null; then
        echo "uv 已经安装，跳过安装"
        return
    fi

    read -p "安装 python && uv？ [y/n]: " install
    if [ "$install" = "y" ]; then
        echo "正在安装 uv..."
        # With pip.
        apt install -y python3 python3-pip
        if [ "$IS_CHINA" -eq 0 ]; then
            pip config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple
        fi
        pip install uv --break-system-packages
    fi
}

install_docker() {
    if command -v docker &>/dev/null; then
        echo "docker 已经安装，跳过安装"
        return
    fi

    read -p "安装 docker？ [y/n]: " install
    if [ "$install" = "y" ]; then
        if [ "$IS_CHINA" -eq 0 ]; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            DOWNLOAD_URL=https://mirrors.ustc.edu.cn/docker-ce sh get-docker.sh
            # 设置 /etc/docker/daemon.json
        sudo mkdir -p /etc/docker
        sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "1"
  }
}
EOF
            # 重启 Docker 服务
            sudo systemctl daemon-reload
            sudo systemctl restart docker
        else
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
        fi
    fi
}


# 根据参数安装组件
install_components() {
    if [ $# -eq 0 ]; then
        # 默认顺序执行
        install_base
        install_zsh
        install_vim
        install_uv
        install_docker
    else
        # 根据传入参数执行
        for component in "$@"; do
            case $component in
                install_base) install_base ;;
                install_zsh) install_zsh ;;
                install_vim) install_vim ;;
                install_uv) install_uv ;;
                install_docker) install_docker ;;
                *) echo "无效组件: $component" ;;
            esac
        done
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

install_components "$@"

echo "初始化完成！"