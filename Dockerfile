# syntax=docker/dockerfile:1.7

# 构建阶段：完整构建，确保 better-sqlite3 正确编译
FROM node:20-alpine AS builder
WORKDIR /app

# 安装编译工具（better-sqlite3 需要）
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    gcc \
    libc-dev \
    musl-dev \
    && rm -rf /var/cache/apk/*

# 复制所有文件
COPY . .

# 使用 npm 安装所有依赖（包括编译 better-sqlite3）
# 使用 --prefer-offline 和 --no-audit 加速构建
RUN npm install --prefer-offline --no-audit --no-fund

# 验证 better-sqlite3 编译结果
RUN echo "🔍 检查 better-sqlite3 编译文件..." && \
    ls -la node_modules/better-sqlite3/build/Release/ 2>/dev/null && \
    echo "✅ better-sqlite3 编译成功" || \
    (echo "❌ better-sqlite3 编译失败" && exit 1)

# 构建应用
RUN NITRO_PRESET=node-server npm run build

# 运行阶段：最小化镜像
FROM node:20-alpine AS runner
WORKDIR /app

# 设置环境变量
ENV NODE_ENV=production
ENV PORT=3000
ENV HOST=0.0.0.0
ENV NITRO_LOG_LEVEL=info

EXPOSE 3000

# 安装运行时依赖（better-sqlite3 需要）
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    gcc \
    libc-dev \
    musl-dev \
    && rm -rf /var/cache/apk/*

# 从构建阶段复制所有必要文件
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.output ./.output
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-lock.yaml ./ 2>/dev/null || true

# 创建 data 目录并设置权限（用于 SQLite 持久化）
RUN mkdir -p /app/data && chmod 777 /app/data

# 验证 better-sqlite3 是否可用（关键步骤）
RUN echo "🔍 验证 better-sqlite3 在运行环境中..." && \
    node -e "try { const db = require('better-sqlite3'); console.log('✅ better-sqlite3 可用'); } catch(e) { console.log('❌', e.message); process.exit(1); }"

CMD ["node", "--enable-source-maps", ".output/server/index.mjs"]
