#!/bin/bash

# Configuration flags
INSTALL_SYSTEM_UPDATES=false
INSTALL_DEV_TOOLS=true
INSTALL_AWS_CLI=false
INSTALL_ANSIBLE=true
INSTALL_DOCKER=true
INSTALL_NODEJS=true
INSTALL_GO=true
INSTALL_POSTGRESQL=true
INSTALL_PGADMIN=true

# Database configuration
DATABASE_DB=dev_db
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres

# エラー発生時にスクリプトを停止
set -e
echo "Begin: User data script execution - $(date)"

# システムアップデート
if [ "$INSTALL_SYSTEM_UPDATES" = true ]; then
    echo "Checking for system updates..."
    dnf check-update > /dev/null 2>&1 || UPDATE_NEEDED=$?
    if [ "$UPDATE_NEEDED" == "100" ]; then
        echo "Updates available. Updating system packages..."
        dnf update -y
    else
        echo "System is up to date."
    fi
fi

# 開発ツールとその他の必要なパッケージのインストール
if [ "$INSTALL_DEV_TOOLS" = true ]; then
    echo "Checking development tools and required packages..."
    
    # Development Toolsグループのチェック
    if ! dnf group list installed "Development Tools" &>/dev/null; then
        echo "Installing Development Tools group..."
        dnf groupinstall "Development Tools" -y
    else
        echo "Development Tools already installed."
    fi
    
    # 個別パッケージのチェックとインストール
    PACKAGES=("git" "make" "jq" "which" "python3-pip" "python3-devel" "libffi-devel" "openssl-devel")
    for pkg in "${PACKAGES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            echo "Installing $pkg..."
            dnf install -y "$pkg"
        else
            echo "$pkg already installed."
        fi
    done
fi

# PostgreSQLのインストールと設定
if [ "$INSTALL_POSTGRESQL" = true ]; then
    if ! command -v psql &>/dev/null; then
        echo "Installing PostgreSQL..."
        
        # PostgreSQL公式リポジトリの追加
        dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        
        # AppStreamのPostgreSQLモジュールを無効化
        dnf -qy module disable postgresql
        
        # PostgreSQLのインストール
        dnf install -y postgresql15-server postgresql15 postgresql15-contrib postgresql15-devel
        
        # PostgreSQLの初期化（データディレクトリが存在しない場合のみ）
        if [ ! -d "/var/lib/pgsql/15/data/base" ]; then
            /usr/pgsql-15/bin/postgresql-15-setup initdb
            
            # PostgreSQL設定の変更
            PG_HBA_CONF="/var/lib/pgsql/15/data/pg_hba.conf"
            POSTGRESQL_CONF="/var/lib/pgsql/15/data/postgresql.conf"
            
            # リッスンアドレスの設定
            sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $POSTGRESQL_CONF
            
            # 認証方式の変更
            sed -i 's/ident/md5/g' $PG_HBA_CONF
            echo "host    all             all             0.0.0.0/0               md5" >> $PG_HBA_CONF
        fi
        
        # PostgreSQLの起動
        systemctl enable postgresql-15
        systemctl start postgresql-15
        
        # データベースの存在確認と作成
        if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DATABASE_DB"; then
            echo "Creating database $DATABASE_DB..."
            sudo -u postgres psql -c "CREATE DATABASE $DATABASE_DB;"
        else
            echo "Database $DATABASE_DB already exists."
        fi
        
        # パスワードの設定（既存のパスワードと異なる場合のみ）
        sudo -u postgres psql -c "ALTER USER $DATABASE_USER WITH PASSWORD '$DATABASE_PASSWORD';"
    else
        echo "PostgreSQL is already installed."
    fi
fi

# pgAdminのインストール
if [ "$INSTALL_PGADMIN" = true ]; then
    if ! rpm -q pgadmin4-web &>/dev/null; then
        echo "Installing pgAdmin..."
        
        # EPELリポジトリの確認と追加
        if ! rpm -q epel-release &>/dev/null; then
            dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        fi
        
        # Apacheとmod_wsgiのインストール
        if ! rpm -q httpd &>/dev/null; then
            echo "Installing Apache and mod_wsgi..."
            dnf install -y httpd httpd-devel mod_wsgi
        fi
        
        # pgAdmin4のインストール
        dnf install -y pgadmin4-web
        
        # mod_wsgi設定の更新（ファイルが存在しない場合のみ）
        if [ ! -f "/etc/httpd/conf.modules.d/10-wsgi.conf" ]; then
            echo "LoadModule wsgi_module modules/mod_wsgi.so" > /etc/httpd/conf.modules.d/10-wsgi.conf
        fi
        
        # SELinuxの設定確認と調整
        if ! getsebool httpd_can_network_connect | grep -q "on$"; then
            setsebool -P httpd_can_network_connect on
        fi
        
        # pgAdmin4-webのセットアップ（初回のみ）
        if [ ! -f "/var/lib/pgadmin/pgadmin4.db" ]; then
            python3 /usr/lib/python3.6/site-packages/pgadmin4-web/setup.py
        fi
        
        # Apacheの起動と自動起動設定
        systemctl enable httpd
        systemctl start httpd
        
        echo "pgAdmin installation completed. Please access http://your-server-ip/pgadmin4 to set up initial admin account."
    else
        echo "pgAdmin is already installed."
    fi
fi

# AWS CLIのインストール
if [ "$INSTALL_AWS_CLI" = true ]; then
    if ! command -v aws &>/dev/null; then
        echo "Installing AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        ./aws/install
        rm -rf aws awscliv2.zip
    else
        echo "AWS CLI is already installed."
    fi
fi

# Ansibleのインストール
if [ "$INSTALL_ANSIBLE" = true ]; then
    if ! command -v ansible &>/dev/null; then
        echo "Installing Ansible..."
        python3 -m pip install ansible
    else
        echo "Ansible is already installed."
    fi
fi

# Dockerのインストール
if [ "$INSTALL_DOCKER" = true ]; then
    if ! command -v docker &>/dev/null; then
        echo "Installing Docker..."
        dnf install -y docker
        systemctl enable docker
        systemctl start docker
        
        echo "Installing Docker Compose..."
        if ! command -v docker-compose &>/dev/null; then
            DOCKER_COMPOSE_VERSION="v2.21.0"
            curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
        
        # ec2-userをdockerグループに追加（まだ追加されていない場合）
        if ! groups ec2-user | grep -q docker; then
            usermod -a -G docker ec2-user
        fi
    else
        echo "Docker is already installed."
    fi
fi

# Node.jsのインストール
if [ "$INSTALL_NODEJS" = true ]; then
    if ! command -v node &>/dev/null; then
        echo "Installing Node.js..."
        dnf install -y nodejs npm
    else
        echo "Node.js is already installed."
    fi
fi

# Go言語のインストール
if [ "$INSTALL_GO" = true ]; then
    if ! command -v go &>/dev/null; then
        echo "Installing Go language..."
        wget "https://go.dev/dl/go1.22.0.linux-amd64.tar.gz"
        rm -rf /usr/local/go
        tar -C /usr/local -xzf "go1.22.0.linux-amd64.tar.gz"
        rm "go1.22.0.linux-amd64.tar.gz"
        
        # PATH設定
        if ! grep -q "/usr/local/go/bin" /home/ec2-user/.bashrc; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/ec2-user/.bashrc
            echo 'export GOPATH=$HOME/go' >> /home/ec2-user/.bashrc
            echo 'export PATH=$PATH:$GOPATH/bin' >> /home/ec2-user/.bashrc
        fi
        
        # GOROOTとGOPATHの設定
        export GOROOT=/usr/local/go
        export GOPATH=$HOME/go
        export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
    else
        echo "Go is already installed."
    fi
fi

# インストールされたバージョンの確認
echo "Checking installed versions..."
echo "System packages updated: $(date)"
[ "$INSTALL_DEV_TOOLS" = true ] && [ -x "$(command -v git)" ] && echo "Git version: $(git --version)"
[ "$INSTALL_DEV_TOOLS" = true ] && [ -x "$(command -v make)" ] && echo "Make version: $(make --version | head -n1)"
[ "$INSTALL_AWS_CLI" = true ] && [ -x "$(command -v aws)" ] && echo "AWS CLI version: $(aws --version)"
[ "$INSTALL_ANSIBLE" = true ] && [ -x "$(command -v ansible)" ] && echo "Ansible version: $(ansible --version | head -n1)"
[ "$INSTALL_DOCKER" = true ] && [ -x "$(command -v docker)" ] && echo "Docker version: $(docker --version)"
[ "$INSTALL_DOCKER" = true ] && [ -x "$(command -v docker-compose)" ] && echo "Docker Compose version: $(docker-compose --version)"
[ "$INSTALL_NODEJS" = true ] && [ -x "$(command -v node)" ] && echo "Node version: $(node -v)"
[ "$INSTALL_GO" = true ] && [ -x "$(command -v go)" ] && echo "Go version: $(go version)"
[ "$INSTALL_POSTGRESQL" = true ] && [ -x "$(command -v psql)" ] && echo "PostgreSQL version: $(psql --version)"

# メタデータの確認
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "End: User data script execution - $(date)"
