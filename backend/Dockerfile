# syntax=docker/dockerfile:1
#
# VibePlan backend image. Multi-stage: deps → build → runtime.
# Targets prod use Postgres — see backend/prisma/schema.prisma.

FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --include=dev

FROM node:20-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps  /app/node_modules ./node_modules
COPY --from=build /app/dist          ./dist
COPY --from=build /app/prisma        ./prisma
COPY package.json ./

EXPOSE 4400
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/index.js"]
