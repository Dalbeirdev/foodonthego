# Everything a browser downloads: the two React shells, the Flutter web build,
# and the nginx that serves them and proxies the API to PHP-FPM.

# --- the React shells ---------------------------------------------------------
FROM node:22-alpine AS react
WORKDIR /src
COPY web/package.json web/package-lock.json ./
COPY web/packages ./packages
COPY web/apps ./apps
COPY web/tsconfig.base.json ./
RUN npm ci
RUN npm run build --workspace apps/restaurant \
    && npm run build --workspace apps/admin

# --- the customer app, as web -------------------------------------------------
#
# The same Flutter version CI pins. A review build produced by a different
# toolchain than the tested one is not the tested app.
FROM ghcr.io/cirruslabs/flutter:3.47.2 AS flutter
WORKDIR /src
COPY mobile/pubspec.yaml mobile/pubspec.lock ./
RUN flutter pub get
COPY mobile/ ./
ARG API_BASE_URL=https://techpio.tech/api/v1
RUN flutter build web --release \
      --dart-define=FOTG_API_BASE_URL=${API_BASE_URL} \
      --dart-define=FOTG_ENV=review

# --- what actually runs -------------------------------------------------------
FROM nginx:alpine

COPY deploy/nginx/app.conf /etc/nginx/conf.d/default.conf

# The API's public directory, for index.php and anything it serves directly.
COPY backend/public /app/public

COPY --from=react  /src/apps/restaurant/dist /var/www/restaurant
COPY --from=react  /src/apps/admin/dist      /var/www/admin
COPY --from=flutter /src/build/web           /var/www/customer

EXPOSE 80
