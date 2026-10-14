# fibrik-ui: the official Caddy image plus the UI build. The build stage runs
# on the build host (static assets are architecture-independent).
FROM --platform=$BUILDPLATFORM node:24.22.0-alpine AS build
WORKDIR /ui
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

FROM caddy:2.11.7
COPY --from=build /ui/dist /srv
