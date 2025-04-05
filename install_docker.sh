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
    if ! ping -c 1 google.com &> /dev/null && ! ping -c 1 baidu.com &> /dev/null; then
        echo "错误: 网络连接异常，请检查网络设置"
        exit 1
    fi
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
        # 更新包索引
        apt-get update

        # 安装必要的依赖
        apt-get install -y \
            apt-transport-https \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # 删除旧的GPG密钥（如果存在）
        rm -f /usr/share/keyrings/docker-archive-keyring.gpg

        # 添加Docker的官方GPG密钥
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

        # 设置稳定版仓库
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        # 更新包索引
        apt-get update

        # 安装Docker Engine
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
            docker-engine

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
docker version
echo "Docker服务状态："
systemctl status docker

trap - EXIT 