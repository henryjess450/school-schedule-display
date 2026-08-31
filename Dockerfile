FROM node:22-alpine

# Timezone matters: the app treats local time as school time, so the container
# must run in the school's zone. Overridden by TZ in docker-compose.yml.
RUN apk add --no-cache tzdata
ENV TZ=America/Vancouver
ENV NODE_ENV=production

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY src ./src
COPY public ./public
COPY config ./config

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/healthz > /dev/null || exit 1

CMD ["node", "src/server.js"]
