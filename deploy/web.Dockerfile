# Everything a browser downloads: the three React applications and the nginx
# that serves them and proxies the API to PHP-FPM.
#
# The customer web app used to be the Flutter app compiled for web. It is now a
# React application of its own (web/apps/customer), which is why no Flutter
# stage remains here: Flutter builds Android and iOS, and the browser gets a
# build made for a browser. The Flutter web bundle was 3.9 MB of main.dart.js
# that painted its text to a canvas and fetched its font from Google's CDN at
# runtime, so a blocked CDN meant an app with no words in it. The React build is
# 249 KB, 79 KB over the wire, and renders real DOM text.

# --- the React shells ---------------------------------------------------------
FROM node:22-alpine AS react
WORKDIR /src
COPY web/package.json web/package-lock.json ./
COPY web/packages ./packages
COPY web/apps ./apps
COPY web/tsconfig.base.json ./
RUN npm ci
RUN npm run build --workspace apps/customer \
    && npm run build --workspace apps/restaurant \
    && npm run build --workspace apps/admin

# --- what actually runs -------------------------------------------------------
FROM nginx:alpine

COPY deploy/nginx/app.conf /etc/nginx/conf.d/default.conf

# The API's public directory, for index.php and anything it serves directly.
COPY backend/public /app/public

COPY --from=react  /src/apps/restaurant/dist /var/www/restaurant
COPY --from=react  /src/apps/admin/dist      /var/www/admin
COPY --from=react  /src/apps/customer/dist   /var/www/customer

EXPOSE 80
