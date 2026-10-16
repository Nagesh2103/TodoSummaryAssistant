# syntax=docker/dockerfile:1.7

# ---------- Stage 1: build the static bundle ----------
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund
COPY public ./public
COPY src ./src
# Build-time API base. Empty => relative "/api", which nginx proxies to the backend,
# so ONE image works in every environment (no rebuild per environment).
ARG REACT_APP_API_BASE_URL=""
ENV REACT_APP_API_BASE_URL=${REACT_APP_API_BASE_URL}
# CI=false: the existing source has a react-hooks lint warning which CRA would
# otherwise treat as an error when CI=true. Lint/tests are enforced in the pipeline.
ENV CI=false
RUN npm run build

# ---------- Stage 2: runtime (unprivileged nginx, runs as UID 101) ----------
FROM nginxinc/nginx-unprivileged:1.27-alpine
# The official entrypoint renders *.template files with envsubst at start-up
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/build /usr/share/nginx/html

# Runtime configuration (override with -e / compose environment)
ENV BACKEND_URL=http://backend:8080 \
    DNS_RESOLVER=127.0.0.11

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
