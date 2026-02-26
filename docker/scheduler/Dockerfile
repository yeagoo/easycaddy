# Scheduler 容器 - 定时版本检查与自动构建
# 安装 curl（API 查询）和 docker-cli（触发构建）
#
# 构建上下文为项目根目录：
#   docker build -f docker/scheduler/Dockerfile .

FROM almalinux:10

# 依赖安装层
RUN dnf install -y curl dnf-plugins-core && \
    dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo && \
    dnf install -y docker-ce-cli docker-compose-plugin && \
    dnf clean all && \
    useradd -r -m -s /sbin/nologin scheduler

# 脚本复制层
COPY docker/scheduler/scheduler.sh /app/scheduler.sh
RUN chmod +x /app/scheduler.sh

USER scheduler
WORKDIR /app
ENTRYPOINT ["/app/scheduler.sh"]
