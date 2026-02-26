# Builder 容器 - 多阶段构建
# 阶段 1：编译 nfpm（Go 工具链仅在此阶段使用）
# 阶段 2：运行时环境（仅包含构建 RPM 所需的依赖）
#
# 构建上下文为项目根目录：
#   docker build -f docker/builder/Dockerfile .

# 阶段 1：安装 nfpm
FROM almalinux:10 AS nfpm-installer
RUN dnf install -y golang && \
    go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest && \
    dnf clean all

# 阶段 2：运行时环境
FROM almalinux:10

# 依赖安装层（变更频率低，利用层缓存）
RUN dnf install -y createrepo_c curl rpm-build rpm-sign gnupg2 && \
    dnf clean all && \
    groupadd -r -g 1500 appuser && \
    useradd -r -m -s /sbin/nologin -u 1500 -g appuser builder

# 从阶段 1 复制 nfpm 二进制
COPY --from=nfpm-installer /root/go/bin/nfpm /usr/local/bin/nfpm

# 脚本复制层（变更频率高，与依赖层分离）
COPY build-repo.sh /app/build-repo.sh
COPY packaging/ /app/packaging/
COPY docker/builder/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /repo && chown builder:builder /repo

USER builder
WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
