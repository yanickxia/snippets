#!/bin/bash

# 脚本说明：
# 这是一个用于初始化 Ubuntu 环境的自动化脚本。
# 功能：
# 1. 自动检测国内外环境，并可手动指定。
# 2. 国内环境自动切换为中科大（USTC）的 apt 和 pip 镜像源。
# 3. 可选择性安装核心组件，包括：基础工具(git, curl), zsh, vim, uv(Python包管理器), Docker。
#
# 使用方法：
# 1. 安装所有默认组件:
#    bash a.sh
#
# 2. 指定安装部分组件 (使用 -m 参数，组件名用引号包裹):
#    bash a.sh -m "install_base install_docker"
#
# 3. 在非 Ubuntu 系统上强制执行 (使用 -f 参数):
#    bash a.sh -f
#    bash a.sh -f -m "install_base"
#
# 4. 显示帮助信息:
#    bash a.sh -h

# 预定义 IS_CHINA，默认为 1（国外环境）
IS_CHINA=1

# 是否强制跳过 Ubuntu 检查
FORCE=0

# 需要安装的组件列表，默认为空
COMPONENTS=""

# 显示帮助信息
display_help() {
    echo "用法: $0 [-f] [-h] [-m \"组件1 组件2 ...\"]"
    echo
    echo "这是一个用于初始化 Ubuntu 环境的自动化脚本。"
    echo
    echo "选项:"
    echo "  -f          强制在非 Ubuntu 系统上执行脚本。"
    echo "  -h          显示此帮助信息并退出。"
    echo "  -m \"...\"    指定要安装的组件列表，用空格分隔并用引号包裹。"
    echo "              如果未提供此选项，将以交互模式询问并安装所有默认组件。"
    echo
    echo "可用组件:"
    echo "  install_base      安装基础工具 (git, curl)"
    echo "  install_zsh       安装 zsh 和 oh-my-zsh"
    echo "  install_vim       安装 vim (会提示确认)"
    echo "  install_uv        安装 Python, pip, 和 uv (会提示确认)"
    echo "  install_docker    安装 Docker (会提示确认)"
    echo
    echo "示例:"
    echo "  bash $0                            # 交互式安装所有组件"
    echo "  bash $0 -m \"install_base install_docker\" # 只安装基础工具和 Docker"
    echo "  bash $0 -f -m \"install_base\"       # 在非 Ubuntu 系统上强制只安装基础工具"
}


# 解析命令行参数
while getopts "fm:h" opt; do
    case $opt in
        f) FORCE=1 ;;
        m) COMPONENTS="$OPTARG" ;;
        h) display_help; exit 0 ;;
        *) display_help; exit 1 ;;
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
    echo "--- 开始安装基础工具 ---"
    apt update
    apt install -y git curl
    check_command git
    check_command curl
    echo "--- 基础工具安装完成 ---"
}

# 安装 oh-my-zsh
install_zsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo "oh-my-zsh 已安装，跳过安装"
        return 0
    fi
    
    echo "--- 开始安装 oh-my-zsh ---"
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
    echo "--- oh-my-zsh 安装完成 ---"
}

# 替换镜像源
replace_mirror() {
    if [ "$IS_CHINA" -eq 0 ]; then
        echo "--- 当前为国内环境，替换为中国科技大学镜像源 ---"
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
        echo "--- 正在安装 vim... ---"
        apt install -y vim
        check_command vim
        echo "--- vim 安装完成 ---"
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
        echo "--- 正在安装 uv... ---"
        apt install -y python3 python3-pip
        if [ "$IS_CHINA" -eq 0 ]; then
            pip3 config set global.index-url https://mirrors.ustc.edu.cn/pypi/simple
        fi
        pip3 install uv --break-system-packages
        check_command uv
        echo "--- uv 安装完成 ---"
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

    echo "--- 正在安装 Docker... ---"
    if [ "$IS_CHINA" -eq 0 ]; then
        echo "检测到中国大陆环境，使用国内镜像源安装 Docker"
        curl -fsSL https://gitea.home.yanick.site:6443/yanick/snippets/raw/branch/master/docker/get-docker.sh | bash -s docker --mirror Aliyun
        if [ $? -ne 0 ]; then
            echo "错误：Docker 安装失败" >&2
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
        rm get-docker.sh
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
  }
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
    echo "--- Docker 安装并配置成功 ---"
    return 0
}

# 根据参数安装组件
install_components() {
    local components_to_install=("$@")
    # 如果没有通过 -m 指定组件，则设置默认安装所有
    if [ ${#components_to_install[@]} -eq 0 ]; then
        components_to_install=(install_base install_zsh install_vim install_uv install_docker)
    fi

    for component in "${components_to_install[@]}"; do
        case $component in
            install_base) install_base ;;
            install_zsh) install_zsh ;;
            install_vim) install_vim ;;
            install_uv) install_uv ;;
            install_docker) install_docker ;;
            *) echo "警告：无效组件名 '$component'，将被忽略。" >&2 ;;
        esac
    done
}

# 主逻辑
main() {
    # 检查 Ubuntu 系统
    check_ubuntu

    # 检查网络环境
    check_location

    # 允许用户交互式覆盖 IS_CHINA
    if [ -t 0 ]; then # 判断是否为交互式终端
        read -p "检测到 IS_CHINA=$IS_CHINA。是否需要手动更改？ [y/n] (直接回车表示不更改): " user_input
        if [ "$user_input" = "y" ] || [ "$user_input" = "Y" ]; then
            read -p "是否为国内环境？ [y/n]: " is_china_confirm
            if [ "$is_china_confirm" = "y" ] || [ "$is_china_confirm" = "Y" ]; then
                IS_CHINA=0
                echo "用户设置为国内环境。"
            elif [ "$is_china_confirm" = "n" ] || [ "$is_china_confirm" = "N" ]; then
                IS_CHINA=1
                echo "用户设置为国外环境。"
            fi
        else
             echo "使用自动检测结果。"
        fi
    else
        echo "非交互式终端，跳过用户输入，使用自动检测的 IS_CHINA 值: $IS_CHINA"
    fi

    # 更新镜像源
    replace_mirror

    # 安装组件
    # 将 $COMPONENTS 传递给函数，shell会自动进行单词分割
    install_components $COMPONENTS

    echo "初始化完成！"
}

# 执行主函数，并将所有非选项参数传递给它
main

