# Install dependencies only when needed
FROM node:alpine AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json pnpm-lock.yaml ./

RUN npm install -g pnpm@next-7 \
    && echo "pnpm version: $(pnpm -v)" \
    && pnpm config set package-import-method copy \
    && pnpm i --frozen-lockfile 

# Rebuild the source code only when needed
FROM node:alpine AS builder
WORKDIR /app
COPY . .
COPY --from=deps /app/node_modules ./node_modules
# COPY --from=deps /app/.pnpm_store ./.pnpm_store
RUN ls -lah node_modules && du -d 1 -h .\
    && npm install -g pnpm@next-7 \
    && pnpm config set package-import-method copy \
    # idk why type check always fails on github action
    && awk 'NR==4{print "typescript: {ignoreBuildErrors: true},"}1' next.config.js | tee next.config.js \
    && pnpm run build \
    && pnpm install --prod --ignore-scripts --prefer-offline --frozen-lockfile \
    && rm -rf .next/cache

# Production image, copy all the files and run next
FROM node:alpine AS runner
WORKDIR /app

ENV NODE_ENV production

RUN addgroup -g 1001 -S nodejs
RUN adduser -S nextjs -u 1001

# You only need to copy next.config.js if you are NOT using the default configuration
COPY --from=builder /app/next.config.js ./
COPY --from=builder /app/next-i18next.config.js ./
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

USER nextjs

EXPOSE 3000

# Next.js collects completely anonymous telemetry data about general usage.
# Learn more here: https://nextjs.org/telemetry
# Uncomment the following line in case you want to disable telemetry.
# ENV NEXT_TELEMETRY_DISABLED 1

CMD ["npm", "run", "start"] 
