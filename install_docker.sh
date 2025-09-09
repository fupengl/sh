#!/bin/bash

# 错误处理
set -e
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "\"${last_command}\" command failed with exit code $?."' EXIT

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
  echo "请使用root用户运行此脚本"
  exit 1
fi

# 检查系统要求
check_system_requirements() {
    # 检查内存
    total_memory=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_memory -lt 2048 ]; then
        echo "警告: 系统内存小于2GB，Docker可能无法正常运行"
        read -p "是否继续安装？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # 检查磁盘空间
    free_space=$(df -m / | awk 'NR==2 {print $4}')
    if [ $free_space -lt 20480 ]; then
        echo "警告: 根目录可用空间小于20GB，建议清理磁盘空间"
        read -p "是否继续安装？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# 检查网络连接
check_network() {
    echo "检查网络连接..."
    local sites=("baidu.com" "mirrors.aliyun.com" "download.docker.com" "google.com")
    local connected=false
    
    for site in "${sites[@]}"; do
        echo "测试连接到 $site..."
        if ping -c 1 -W 5 $site &> /dev/null; then
            echo "网络连接正常 ($site)"
            connected=true
            break
        fi
    done
    
    if [ "$connected" = false ]; then
        echo "警告: 网络连接可能存在问题，但继续尝试安装..."
        echo "如果安装失败，请检查网络设置或防火墙配置"
    fi
}

# 清理旧的Docker安装
cleanup_old_docker() {
    echo "清理旧的Docker安装..."
    # 删除旧的GPG密钥和仓库文件
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/sources.list.d/docker-ce.list
    
    # 清理可能存在的旧Docker安装
    apt-get remove -y docker docker-engine docker.io containerd runc || true
}

echo "开始安装Docker..."

# 检查系统要求
check_system_requirements

# 检查网络连接
check_network

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
fi

case $OS in
    "ubuntu"|"debian")
        # Ubuntu/Debian安装流程
        echo "检测到 ${OS} ${VERSION_ID} 系统"
        
        # 清理旧的安装
        cleanup_old_docker
        
        # 更新包索引
        apt-get update

        # 安装必要的依赖
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # 创建密钥目录
        mkdir -p /usr/share/keyrings/

        # 添加Docker的官方GPG密钥
        echo "添加Docker GPG密钥..."
        
        # 定义多个GPG密钥源
        gpg_sources=(
            "https://download.docker.com/linux/ubuntu/gpg"
            "https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg"
            "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg"
            "https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg"
        )
        
        gpg_success=false
        for gpg_url in "${gpg_sources[@]}"; do
            echo "尝试从 $gpg_url 下载GPG密钥..."
            if curl -fsSL --connect-timeout 10 --max-time 30 "$gpg_url" | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
                echo "GPG密钥下载成功"
                gpg_success=true
                break
            else
                echo "从 $gpg_url 下载失败，尝试下一个源..."
            fi
        done
        
        if [ "$gpg_success" = false ]; then
            echo "错误: 无法从任何源下载GPG密钥，请检查网络连接"
            exit 1
        fi

        # 设置稳定版仓库
        echo "添加Docker仓库..."
        
        # 定义多个Docker仓库源
        repo_sources=(
            "https://download.docker.com/linux/ubuntu"
            "https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
            "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu"
            "https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu"
        )
        
        repo_success=false
        for repo_url in "${repo_sources[@]}"; do
            echo "尝试使用仓库源: $repo_url"
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $repo_url \
              $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # 测试仓库连接
            if timeout 30 apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/docker.list -o Dir::Etc::sourceparts=/dev/null; then
                echo "Docker仓库配置成功"
                repo_success=true
                break
            else
                echo "仓库源 $repo_url 连接失败，尝试下一个..."
                rm -f /etc/apt/sources.list.d/docker.list
            fi
        done
        
        if [ "$repo_success" = false ]; then
            echo "错误: 无法连接到任何Docker仓库源"
            exit 1
        fi

        # 更新包索引
        echo "更新包列表..."
        apt-get update

        # 安装Docker Engine
        echo "安装Docker..."
        apt-get install -y docker-ce docker-ce-cli containerd.io
        ;;
        
    "centos"|"rhel"|"fedora")
        # CentOS/RHEL/Fedora安装流程
        echo "检测到 ${OS} ${VERSION_ID} 系统"
        # 删除旧版本Docker（如果存在）
        yum remove -y docker \
            docker-client \
            docker-client-latest \
            docker-common \
            docker-latest \
            docker-latest-logrotate \
            docker-logrotate \
            docker-engine || true

        # 安装必要的依赖
        yum install -y yum-utils

        # 添加Docker仓库
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

        # 安装Docker Engine
        yum install -y docker-ce docker-ce-cli containerd.io
        ;;
        
    *)
        echo "不支持的操作系统: ${OS}"
        exit 1
        ;;
esac

# 创建Docker配置目录
mkdir -p /etc/docker

# 配置Docker镜像加速
cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.registry.cyou",
    "https://docker-cf.registry.cyou",
    "https://dockercf.jsdelivr.fyi",
    "https://docker.jsdelivr.fyi",
    "https://dockertest.jsdelivr.fyi",
    "https://mirror.aliyuncs.com",
    "https://dockerproxy.com",
    "https://mirror.baidubce.com",
    "https://docker.m.daocloud.io",
    "https://docker.nju.edu.cn",
    "https://docker.mirrors.sjtug.sjtu.edu.cn",
    "https://docker.mirrors.ustc.edu.cn",
    "https://mirror.iscas.ac.cn",
    "https://docker.rainbond.cc"
  ]
}
EOF

# 启动Docker服务
systemctl start docker

# 设置Docker开机自启动
systemctl enable docker

# 验证安装
echo "验证Docker安装..."
if ! docker --version; then
    echo "Docker安装可能存在问题，请检查以上错误信息"
    exit 1
fi

if ! systemctl is-active --quiet docker; then
    echo "Docker服务未能正常启动，请检查系统日志"
    exit 1
fi

echo "Docker安装和配置完成！"
echo "Docker版本信息："
docker --version
echo "Docker服务状态："
systemctl status docker --no-pager -l

trap - EXIT