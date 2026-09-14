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
#
# INSTALLED FROM GOOGLE'S OWN ARCHIVE, not from a third party's image. This
# stage was `FROM ghcr.io/cirruslabs/flutter:3.47.2`, and that tag does not
# exist — the build died with "failed to resolve source metadata ... not found"
# the first time it was ever run. Whether cirruslabs never published 3.47.2 or
# stopped publishing does not much matter: pinning the toolchain to a tag
# somebody else controls means the build breaks when they retire it, and the
# obvious repair under time pressure is to slacken the pin to `:stable` — which
# is exactly what the comment above forbids.
#
# The checksum is the version's own, published in the release index beside the
# archive. It is here so a corrupted or substituted download fails loudly rather
# than producing a review build from an unknown toolchain.
#
# `toolchain_versions_agree_test.dart` holds the version to CI's and the
# checksum to being actually verified.
FROM debian:bookworm-slim AS flutter

ARG FLUTTER_VERSION=3.47.2
ARG FLUTTER_SHA256=447878859d01ca9bfdb99a85f245af07ed8a15fedcd9d189c4749e8e92d1f185

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/flutter.tar.xz \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Flutter refuses to run inside a git checkout it does not own, which is what
# unpacking the archive as root and then building as root produces.
RUN git config --global --add safe.directory /opt/flutter \
    && flutter --version

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
