# Repo Manager 容器 - 管理 API 服务（可选）
# 安装 socat（HTTP 监听）、curl、docker-cli
#
# 构建上下文为项目根目录：
#   docker build -f docker/repo-manager/Dockerfile .

FROM almalinux:10

# 依赖安装层
RUN dnf install -y socat curl dnf-plugins-core && \
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo && \
    dnf install -y docker-ce-cli docker-compose-plugin && \
    dnf clean all && \
    useradd -r -m -s /sbin/nologin manager

# 脚本复制层
COPY build-repo.sh /app/build-repo.sh
COPY packaging/ /app/packaging/
COPY docker/repo-manager/manager.sh /app/manager.sh
RUN chmod +x /app/manager.sh

USER manager
WORKDIR /app
ENTRYPOINT ["/app/manager.sh"]
