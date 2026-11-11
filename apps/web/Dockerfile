FROM node:22.16.0-alpine AS base
RUN npm install --global pnpm@12.18.0
WORKDIR /repo

FROM base AS deps
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml turbo.json ./
COPY apps/web/package.json apps/web/package.json
COPY packages/ui/package.json packages/ui/package.json
COPY packages/api-client/package.json packages/api-client/package.json
COPY packages/config/package.json packages/config/package.json
RUN pnpm install --frozen-lockfile

FROM deps AS builder
COPY . .
RUN pnpm --filter @flowlesshub/web build

FROM node:22.16.0-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs
COPY --from=builder --chown=nextjs:nodejs /repo/apps/web/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /repo/apps/web/.next/static ./apps/web/.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "apps/web/server.js"]
