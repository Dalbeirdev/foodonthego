# The Laravel API.
#
# PHP 8.4 to match what CI tests against. A deployment on a different minor
# version than the one the test suite runs on is a deployment nobody has tested.
FROM php:8.4-fpm-alpine

RUN apk add --no-cache icu-dev oniguruma-dev libzip-dev $PHPIZE_DEPS \
    && docker-php-ext-install pdo_mysql intl mbstring zip bcmath opcache \
    && pecl install redis && docker-php-ext-enable redis \
    && apk del $PHPIZE_DEPS

# OPcache on, because this is a long-running server and the alternative is
# recompiling every file on every request.
RUN { \
      echo 'opcache.enable=1'; \
      echo 'opcache.validate_timestamps=0'; \
      echo 'opcache.memory_consumption=128'; \
    } > /usr/local/etc/php/conf.d/opcache.ini

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Dependencies first, so a code change does not re-resolve the whole tree.
COPY backend/composer.json backend/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

COPY backend/ ./
RUN composer dump-autoload --optimize --no-dev \
    && mkdir -p storage/logs storage/framework/{cache,sessions,views} bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache

USER www-data

EXPOSE 9000
CMD ["php-fpm"]
