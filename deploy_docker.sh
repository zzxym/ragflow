#!/bin/bash

# ==================================
# 环境参数配置
# ==================================
PROJECT_DIR="${HOME}/ragflow_prod"
SERVICE_PASSWORD="Aa123456"  # 统一密码
DOC_ENGINE="elasticsearch"  # 可选 "infinity"
PYTHON_VERSION="3.10"

# ==================================
# 系统初始化
# ==================================
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git python3 python3-pip docker.io docker-compose npm

# 启动 Docker 服务
sudo systemctl enable --now docker
sudo usermod -aG docker ${USER}

# 设置 Elasticsearch 所需内核参数（永久生效）
sudo tee /etc/sysctl.d/99-ragflow.conf <<EOF
vm.max_map_count=262144
EOF
sudo sysctl --system

# ==================================
# 创建项目目录
# ==================================
mkdir -p ${PROJECT_DIR}/{config,data}
cd ${PROJECT_DIR}

# ==================================
# 编写 Docker Compose 配置
# ==================================
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  # -------------------- MySQL --------------------
  mysql:
    image: mysql:8.0
    environment:
      - MYSQL_ROOT_PASSWORD=${SERVICE_PASSWORD}
      - MYSQL_DATABASE=ragflow
      - MYSQL_USER=ragflow
      - MYSQL_PASSWORD=${SERVICE_PASSWORD}
    volumes:
      - ./data/mysql:/var/lib/mysql
    ports:
      - "3306:3306"
    restart: always

  # -------------------- Redis --------------------
  redis:
    image: redis:7.0
    environment:
      - REDIS_PASSWORD=${SERVICE_PASSWORD}
    volumes:
      - ./data/redis:/data
    ports:
      - "6379:6379"
    restart: always

  # -------------------- MinIO --------------------
  minio:
    image: minio/minio:latest  # 修改为最新版本
    environment:
      - MINIO_ROOT_USER=ragflow
      - MINIO_ROOT_PASSWORD=${SERVICE_PASSWORD}
    command: server /data
    volumes:
      - ./data/minio:/data
    ports:
      - "9000:9000"
    restart: always

  # -------------------- Elasticsearch --------------------
  elasticsearch:
    image: elasticsearch:8.12.1
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - "ES_JAVA_OPTS=-Xms4g -Xmx4g"  # 生产环境建议分配足够内存
      - ELASTIC_PASSWORD=${SERVICE_PASSWORD}
    volumes:
      - ./data/elasticsearch:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
      - "9300:9300"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    restart: always

  # -------------------- Infinity（可选，如需替换 Elasticsearch）--------------------
  # infinity:
  #   image: infiniflow/infinity:latest
  #   environment:
  #     - INFINITY_DB_NAME=default_db
  #     - INFINITY_PASSWORD=${SERVICE_PASSWORD}
  #   ports:
  #     - "23817:23817"
  #   restart: always

EOF

# ==================================
# 启动依赖服务
# ==================================
docker-compose up -d

# 等待服务就绪（最多 60 秒）
echo "等待依赖服务启动..."
for i in {1..60}; do
    if docker ps -f "name=mysql" --format "{{.Status}}" | grep -q "Up"; then
        docker exec mysql mysql -uroot -p${SERVICE_PASSWORD} -e "SHOW DATABASES;" >/dev/null 2>&1 && break
    fi
    if docker ps -f "name=elasticsearch" --format "{{.Status}}" | grep -q "Up"; then
        curl -s -u elastic:${SERVICE_PASSWORD} http://localhost:9200/_cluster/health | grep -q "status\":\"green\"" && break
    fi
    sleep 1
done

# ==================================
# 配置 RAGFlow 基础环境变量
# ==================================
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
# 提示后续操作
# ==================================
echo -e "\n\n✅ 依赖服务部署完成！"
echo "下一步请执行："
echo "1. 克隆 RAGFlow 项目："
echo "   git clone https://github.com/infiniflow/ragflow.git"
echo "2. 进入项目目录并安装依赖："
echo "   cd ragflow"
echo "   python -m venv .venv && source .venv/bin/activate"
echo "   pipx install uv && uv sync --python ${PYTHON_VERSION} --all-extras"
echo "3. 复制本目录中的 .env 到 ragflow/docker/ 并启动后端："
echo "   cp ${PROJECT_DIR}/.env ragflow/docker/."
echo "   bash ragflow/docker/launch_backend_service.sh"
echo "4. 启动前端服务："
echo "   cd ragflow/web && npm install && npm run dev"
    
