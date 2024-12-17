#!/bin/bash

# エラー発生時にスクリプトを停止
set -e

# ログファイルの設定
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Begin: User data script execution - $(date)"

# システムアップデート
echo "Updating system packages..."
dnf update -y

# 開発ツールとその他の必要なパッケージのインストール
echo "Installing development tools and required packages..."
dnf groupinstall "Development Tools" -y
dnf install -y \
    git \
    make \
    jq \
    which \
    python3-pip \
    python3-devel \
    libffi-devel \
    openssl-devel

# AWS CLIのインストール
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Ansibleのインストール
echo "Installing Ansible..."
python3 -m pip install --upgrade pip
python3 -m pip install ansible

# Dockerのインストール
echo "Installing Docker..."
dnf install -y docker
systemctl enable docker
systemctl start docker

# Docker Composeのインストール
echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="v2.21.0"
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# ec2-userをdockerグループに追加
usermod -a -G docker ec2-user

# バージョン確認
echo "Checking installed versions..."
echo "System packages updated: $(date)"
echo "Git version: $(git --version)"
echo "Make version: $(make --version | head -n1)"
echo "AWS CLI version: $(aws --version)"
echo "Ansible version: $(ansible --version | head -n1)"
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version)"

# 完了メッセージ
echo "End: User data script execution - $(date)"

# メタデータの確認を待機
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"