FROM node:22-alpine
ENV NODE_ENV=production MARVIN_HOST=0.0.0.0 MARVIN_PORT=8787 MARVIN_DATA_DIR=/data
WORKDIR /app
COPY --chown=node:node server ./server
COPY --chown=node:node scripts ./scripts
COPY --chown=node:node package.json ./package.json
RUN mkdir -p /data && chown -R node:node /data
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD node -e "fetch('http://127.0.0.1:8787/api/health/live').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server/server.mjs"]
