#!/bin/bash

# ==================================
# 环境参数配置
# ==================================
PROJECT_DIR="${HOME}/ragflow_prod"
SERVICE_PASSWORD="Aa123456"  # 统一密码
DOC_ENGINE="elasticsearch"  # 可选 "infinity"，需手动替换部署步骤
PYTHON_VERSION="3.10"

# ==================================
# 系统初始化
# ==================================
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git python3 python3-pip python3-venv nodejs npm

# 安装 Elasticsearch 8.11.3（非 Docker 方式）
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elasticsearch-8.x.list
sudo apt update && sudo apt install -y elasticsearch=8.11.3

# 配置 Elasticsearch 密码
sudo /usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto --batch  # 仅设置 elastic 用户密码
sudo sed -i "s/^#\?xpack.security.enabled.*/xpack.security.enabled: true/" /etc/elasticsearch/elasticsearch.yml
sudo systemctl enable --now elasticsearch
echo -e "${SERVICE_PASSWORD}\n${SERVICE_PASSWORD}" | sudo /usr/share/elasticsearch/bin/elasticsearch-change-password -u elastic

# 安装 MySQL 8.0
sudo apt install -y mysql-server=8.0.34-0ubuntu0.22.04.1
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${SERVICE_PASSWORD}';"
sudo mysql -e "CREATE DATABASE ragflow;"
sudo mysql -e "CREATE USER 'ragflow'@'%' IDENTIFIED BY '${SERVICE_PASSWORD}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ragflow.* TO 'ragflow'@'%';"
sudo systemctl enable --now mysql

# 安装 Redis 7.0
sudo apt install -y redis-server=7.0.12-1ubuntu22.04.1
sudo sed -i "s/^#\?requirepass.*/requirepass ${SERVICE_PASSWORD}/" /etc/redis/redis.conf
sudo systemctl enable --now redis-server

# 安装 MinIO
MINIO_VERSION="RELEASE.2023-10-10T17-10-42Z"
wget https://dl.min.io/server/minio/release/linux-amd64/minio-${MINIO_VERSION}.tar.gz
tar -xzf minio-${MINIO_VERSION}.tar.gz
sudo mv minio-${MINIO_VERSION}/minio /usr/local/bin/
sudo useradd -r -s /sbin/nologin minio
sudo mkdir -p /data/minio
sudo chown -R minio:minio /data/minio
cat > /etc/systemd/system/minio.service <<EOF
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io
Wants=network-online.target
After=network-online.target

[Service]
User=minio
Group=minio
Type=simple
Environment="MINIO_ROOT_USER=ragflow" "MINIO_ROOT_PASSWORD=${SERVICE_PASSWORD}"
ExecStart=/usr/local/bin/minio server /data/minio

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now minio.service

# ==================================
# 配置系统内核参数（Elasticsearch 所需）
# ==================================
sudo tee /etc/sysctl.d/99-ragflow.conf <<EOF
vm.max_map_count=262144
EOF
sudo sysctl --system

# ==================================
# 创建项目目录并配置环境变量
# ==================================
mkdir -p ${PROJECT_DIR}/{conf,data}
cd ${PROJECT_DIR}

# 编写 RAGFlow 环境配置
cat > .env <<EOF
# 文档引擎
DOC_ENGINE=${DOC_ENGINE}

# Elasticsearch 配置
ES_HOST=localhost
ES_PORT=9200
ELASTIC_PASSWORD=${SERVICE_PASSWORD}

# MySQL 配置
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_DBNAME=ragflow
MYSQL_USER=ragflow
MYSQL_PASSWORD=${SERVICE_PASSWORD}

# MinIO 配置
MINIO_HOST=localhost:9000
MINIO_USER=ragflow
MINIO_PASSWORD=${SERVICE_PASSWORD}

# Redis 配置
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=${SERVICE_PASSWORD}
EOF

# ==================================
# 安装 RAGFlow 依赖
# ==================================
git clone https://github.com/infiniflow/ragflow.git
cd ragflow/
python3 -m venv .venv
source .venv/bin/activate
pipx install uv
uv sync --python ${PYTHON_VERSION} --all-extras

# ==================================
# 提示后续操作
# ==================================
echo -e "\n\n✅ 依赖服务部署完成！"
echo "下一步请执行："
echo "1. 配置后端服务："
echo "   source .venv/bin/activate"
echo "   export PYTHONPATH=\$(pwd)"
echo "   bash docker/launch_backend_service.sh"
echo "2. 启动前端服务："
echo "   cd web"
echo "   npm install && npm run dev"
echo "3. 访问系统：http://localhost:5173"
echo "   （生产环境建议使用 Nginx 代理，配置 HTTPS）"
