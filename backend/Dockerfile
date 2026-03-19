# Render / Linux: @tensorflow/tfjs-node needs either matching prebuilds or a native compile.
# The stock Node runtime image often lacks g++/make/python3; this Debian image includes them.
FROM node:20-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY src ./src

ENV NODE_ENV=production

# Render injects PORT; listen uses process.env.PORT || 8080 in src/index.js
CMD ["node", "src/index.js"]
