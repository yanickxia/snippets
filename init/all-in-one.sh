#!/bin/bash

# 预定义 IS_CHINA，默认为 1（国外环境）
IS_CHINA=1

# 是否强制跳过 Ubuntu 检查
FORCE=0

# 解析命令行参数
while getopts "f" opt; do
    case $opt in
        f) FORCE=1 ;;
        *) echo "无效参数: -$opt" >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# 检查是否为 Ubuntu 系统
check_ubuntu() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "ubuntu" ]; then
            if [ "$FORCE" -eq 1 ]; then
                echo "警告：当前系统为 $ID，非 Ubuntu 系统，但由于 -f 参数，强制继续执行" >&2
                return 0
            else
                echo "错误：此脚本仅支持 Ubuntu 系统，当前系统为 $ID" >&2
                exit 1
            fi
        fi
        echo "检测到 Ubuntu 系统：$VERSION"
    else
        if [ "$FORCE" -eq 1 ]; then
            echo "警告：无法检测系统类型，缺少 /etc/os-release，但由于 -f 参数，强制继续执行" >&2
            return 0
        else
            echo "错误：无法检测系统类型，缺少 /etc/os-release" >&2
            exit 1
        fi
    fi
}

# 检查并更新 location 的结果
check_location() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "错误：curl 未安装，请先安装 curl" >&2
        exit 1
    fi

    response=$(curl -s https://myip.ipip.net/json)
    if [ $? -ne 0 ]; then
        echo "警告：无法访问 https://myip.ipip.net/json，使用默认 IS_CHINA 值" >&2
        return 1
    fi

    if echo "$response" | grep -q '"中国"'; then
        IS_CHINA=0
        echo "检测到中国大陆环境"
    else
        IS_CHINA=1
        echo "检测到非中国大陆环境"
    fi
}

# 安装基础工具
install_base() {
    apt update
    apt install -y git curl
    check_command git
    check_command curl
}

# 安装 oh-my-zsh
install_zsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "oh-my-zsh 已安装，跳过安装"
        return 0
    fi

    apt install -y git zsh
    if [ "$IS_CHINA" -eq 0 ]; then
        echo "当前为国内环境，使用清华源安装 oh-my-zsh"
        git clone https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git
        if [ $? -ne 0 ]; then
            echo "错误：无法克隆 oh-my-zsh 仓库" >&2
            return 1
        fi
        cd ohmyzsh/tools || exit 1
        REMOTE=https://mirrors.tuna.tsinghua.edu.cn/git/ohmyzsh.git sh install.sh --unattended
        cd ../.. && rm -rf ohmyzsh
        chsh -s /usr/bin/zsh
    else
        echo "当前为国外环境，安装 oh-my-zsh"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        if [ $? -ne 0 ]; then
            echo "错误：oh-my-zsh 安装失败" >&2
            return 1
        fi
    fi
    check_command zsh
}

# 替换镜像源
replace_mirror() {
    if [ "$IS_CHINA" -eq 0 ]; then
        echo "当前为国内环境，替换为中国科技大学镜像源"
        sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list
        sed -i 's@//.*security.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list
        apt update
    fi
}

# 通用函数：检查命令是否安装并输出版本
check_command() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        echo "$cmd 已成功安装，版本：$($cmd --version | head -n 1)"
    else
        echo "错误：$cmd 安装失败，请检查错误信息！" >&2
        exit 1
    fi
}

# 安装 vim
install_vim() {
    if command -v vim &>/dev/null; then
        echo "vim 已安装，跳过安装"
        return 0
    fi

    read -p "是否安装 vim？ [y/n]: " install
    if [ "$install" = "y" ] || [ "$install" = "Y" ]; then
        echo "正在安装 vim..."
        apt install -y vim
        check_command vim
    else
        echo "用户取消 vim 安装"
        return 0
    fi
}

# 安装 uv
install_uv() {
    if command -v uv &>/dev/null; then
        echo "uv 已安装，跳过安装"
        return 0
    fi

    read -p "是否安装 Python 和 uv？ [y/n]: " install
    if [ "$install" = "y" ] || [ "$install" = "Y" ]; then
        echo "正在安装 uv..."
        apt install -y python3 python3-pip
        if [ "$IS_CHINA" -eq 0 ]; then
            pip3 config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple
        fi
        pip3 install uv --break-system-packages
        check_command uv
    else
        echo "用户取消 uv 安装"
        return 0
    fi
}

# 安装 Docker
install_docker() {
    if command -v docker &>/dev/null; then
        echo "Docker 已安装，跳过安装"
        return 0
    fi

    read -p "是否安装 Docker？ [y/n]: " install
    if [ "$install" != "y" ] && [ "$install" != "Y" ]; then
        echo "用户取消 Docker 安装"
        return 1
    fi

    if [ "$IS_CHINA" -eq 0 ]; then
        echo "检测到中国大陆环境，使用国内镜像源安装 Docker"
        curl -fsSL https://ams-cn-beijing.tos-cn-beijing.volces.com/scripts/get-docker.sh | bash -s docker --mirror Aliyun
        if [ $? -ne 0 ]; then
            echo "错误：无法下载 Docker 安装脚本" >&2
            return 1
        fi
    else
        echo "使用官方源安装 Docker"
        curl -fsSL https://get.docker.com -o get-docker.sh
        if [ $? -ne 0 ]; then
            echo "错误：无法下载 Docker 安装脚本" >&2
            return 1
        fi
        sh get-docker.sh
    fi

    if ! command -v docker &>/dev/null; then
        echo "错误：Docker 安装失败" >&2
        return 1
    fi

    echo "配置 Docker daemon.json"
    sudo mkdir -p /etc/docker
    sudo tee /etc/docker/daemon.json <<-EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "1"
  },
  "registry-mirrors": [
    "https://registry.docker-cn.com"
  ]
}
EOF

    echo "重启 Docker 服务"
    sudo systemctl daemon-reload
    if ! sudo systemctl restart docker; then
        echo "错误：Docker 服务重启失败" >&2
        return 1
    fi

    if ! sudo systemctl is-active --quiet docker; then
        echo "错误：Docker 服务未运行" >&2
        return 1
    fi

    check_command docker
    echo "Docker 安装并配置成功"
    return 0
}

# 根据参数安装组件
install_components() {
    if [ $# -eq 0 ]; then
        install_base
        install_zsh
        install_vim
        install_uv
        install_docker
    else
        for component in "$@"; do
            case $component in
                install_base) install_base ;;
                install_zsh) install_zsh ;;
                install_vim) install_vim ;;
                install_uv) install_uv ;;
                install_docker) install_docker ;;
                *) echo "无效组件: $component" >&2 ;;
            esac
        done
    fi
}

# 主逻辑
main() {
    # 检查 Ubuntu 系统
    # check_ubuntu

    # 检查网络环境
    check_location

    # 允许用户交互式覆盖 IS_CHINA
    if [ -t 0 ]; then
        read -p "是否国内环境？ [y/n]: " user_input
        if [ "$user_input" = "y" ] || [ "$user_input" = "Y" ]; then
            IS_CHINA=0
        elif [ "$user_input" = "n" ] || [ "$user_input" = "N" ]; then
            IS_CHINA=1
        else
            echo "无效输入，使用自动检测的 IS_CHINA 值: $IS_CHINA" >&2
        fi
    else
        echo "非交互式终端，跳过用户输入，使用自动检测的 IS_CHINA 值: $IS_CHINA" >&2
    fi

    # 更新镜像源
    replace_mirror

    # 安装组件
    install_components "$@"

    echo "初始化完成！"
}

# 执行主函数
main "$@"