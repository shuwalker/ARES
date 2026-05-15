# Multi-stage Dockerfile for Claude Code Agent Monitor - a Node.js server with a React client.
# This setup optimizes the final image size by separating the build and runtime stages.
# The first stage installs only the production dependencies for the server, while the second stage builds the React client.
# The final stage combines the necessary files and dependencies to run the application in production.
# Compatibility: This setup is compatible with both Podman and Docker. Runnable on any platform that supports Node.js and Alpine Linux.
#
# Author: Son Nguyen <hoangson091104@gmail.com>

# ── Stage 1: Install server production deps ───────────────────────────
FROM node:22-alpine AS server-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ── Stage 2: Build React client ───────────────────────────────────────
FROM node:22-alpine AS client-build
WORKDIR /app/client
COPY client/package.json client/package-lock.json ./
RUN npm ci
COPY client/ ./
RUN npm run build

# ── Stage 3: Production runtime ───────────────────────────────────────
FROM node:22-alpine
WORKDIR /app

COPY --from=server-deps /app/node_modules ./node_modules/
COPY package.json ./
COPY server/ ./server/
COPY scripts/ ./scripts/
COPY statusline/ ./statusline/
COPY --from=client-build /app/client/dist ./client/dist/

RUN mkdir -p data

EXPOSE 4820

ENV NODE_ENV=production

CMD ["node", "server/index.js"]
