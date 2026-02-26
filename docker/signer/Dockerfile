# Signer 容器 - 最小依赖集
# 仅安装 GPG 签名所需工具（gnupg2、rpm-sign）
# 镜像体积目标小于 200MB
#
# 构建上下文为项目根目录：
#   docker build -f docker/signer/Dockerfile .

FROM almalinux:10

# 依赖安装层（仅签名所需的最小依赖集）
RUN dnf install -y gnupg2 rpm-sign && \
    dnf clean all && \
    groupadd -r -g 1500 appuser && \
    useradd -r -m -s /sbin/nologin -u 1500 -g appuser signer

# 脚本复制层（与依赖层分离，利用层缓存）
COPY build-repo.sh /app/build-repo.sh
COPY packaging/ /app/packaging/
COPY docker/signer/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /repo && chown signer:signer /repo

USER signer
WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
