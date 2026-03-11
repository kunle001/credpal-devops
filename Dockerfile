# ─────────────────────────────────────────────
# Stage 1 – Dependencies (build stage)
# ─────────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

# Copy only manifests first to leverage layer caching
COPY app/package*.json ./

# Install production dependencies only
RUN npm ci --omit=dev

# ─────────────────────────────────────────────
# Stage 2 – Test runner (CI only, not shipped)
# ─────────────────────────────────────────────
FROM node:20-alpine AS test

WORKDIR /app

COPY app/package*.json ./
RUN npm ci

COPY app/ .

RUN npm test

# ─────────────────────────────────────────────
# Stage 3 – Production image
# ─────────────────────────────────────────────
FROM node:20-alpine AS production

# Security: upgrade all OS packages first to patch known CVEs, then install tools
# hadolint ignore=DL3018
RUN apk upgrade --no-cache && \
    apk add --no-cache dumb-init wget

# Upgrade npm to latest patched version (bundled npm may contain CVEs)
RUN npm install -g npm@latest --ignore-scripts

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser  -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copy production deps from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy application source
COPY app/src ./src
COPY app/package*.json ./

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# Use dumb-init as PID 1 to handle signals correctly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/index.js"]
