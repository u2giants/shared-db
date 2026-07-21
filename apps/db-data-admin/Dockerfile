FROM node:24-alpine AS build
WORKDIR /app
ARG VITE_BUILD_SHA=unknown
ENV VITE_BUILD_SHA=$VITE_BUILD_SHA
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.29-alpine
ENV NGINX_ENVSUBST_FILTER=^DB_DATA_ADMIN_
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/health || exit 1
