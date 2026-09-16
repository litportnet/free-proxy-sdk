FROM node:24-bookworm-slim AS build

WORKDIR /app

COPY packages/js/package.json packages/js/package-lock.json ./packages/js/
RUN cd packages/js && npm ci --omit=dev

COPY scripts/build-js.mjs ./scripts/build-js.mjs
COPY packages/js/src ./packages/js/src
RUN node scripts/build-js.mjs

FROM node:24-bookworm-slim

WORKDIR /app
COPY --from=build --chown=node:node /app/packages/js/package.json ./packages/js/package.json
COPY --from=build --chown=node:node /app/packages/js/dist ./packages/js/dist

USER node
ENTRYPOINT ["node", "/app/packages/js/dist/cli.cjs"]
