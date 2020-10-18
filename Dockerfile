FROM php:7.4.11-fpm

MAINTAINER Apiki Team Maintainers "mesaque.silva@apiki.com"

ENV DEBIAN_FRONTEND noninteractive
ENV NGINX_PATH /usr/local/openresty/nginx/conf
ENV NPS_VERSION 1.13.35.2-stable
ENV OPENRESTY_VERSION 1.17.8.2
ENV OPEN_SSL 1.1.1d
ENV PSOL_VERSION 1.13.35.2-x64
ENV WORDPRESS_VERSION 5.5.1
ENV WORDPRESS_SHA1 d3316a4ffff2a12cf92fde8bfdd1ff8691e41931


RUN apt-get update &&\
    apt-get -y install libreadline-dev libncurses5-dev libpcre3-dev \
    libssl-dev perl make build-essential git wget zlib1g-dev libpcre3 unzip curl uuid-dev \
    msmtp libzip-dev libxml2-dev  imagemagick libmagickwand-dev libmagickcore-dev libmcrypt-dev libmemcached-dev ghostscript

RUN apt-get install -y \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libjpeg-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd

RUN echo '' | pecl install -f memcached
RUN echo '' | pecl install -f imagick-3.4.4
RUN echo '' | pecl install -f mcrypt
RUN echo '' | pecl install -f redis

# Clean
RUN apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN set -eux; \
	docker-php-ext-enable opcache; \
	{ \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
		echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
		echo 'display_errors = Off'; \
		echo 'display_startup_errors = Off'; \
		echo 'log_errors = On'; \
		echo 'error_log = /dev/stderr'; \
		echo 'log_errors_max_len = 1024'; \
		echo 'ignore_repeated_errors = On'; \
		echo 'ignore_repeated_source = Off'; \
		echo 'html_errors = Off'; \
	} > /usr/local/etc/php/conf.d/error-logging.ini

RUN docker-php-ext-install zip mysqli sockets soap calendar bcmath opcache exif iconv ftp
RUN docker-php-ext-enable  redis imagick mcrypt memcached

RUN cd /usr/bin && curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && mv /usr/bin/wp-cli.phar /usr/bin/wp && chmod +x /usr/bin/wp

RUN cd / && /usr/bin/wget https://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz && tar -xzf openresty-${OPENRESTY_VERSION}.tar.gz
RUN cd  /openresty-${OPENRESTY_VERSION} && /usr/bin/wget https://github.com/apache/incubator-pagespeed-ngx/archive/v${NPS_VERSION}.zip \
&& /usr/bin/wget https://www.openssl.org/source/openssl-${OPEN_SSL}.tar.gz \
&& tar -xzf openssl-${OPEN_SSL}.tar.gz \
&& unzip -x v${NPS_VERSION}.zip \
&& cd incubator-pagespeed-ngx-${NPS_VERSION} \
&& /usr/bin/wget https://dl.google.com/dl/page-speed/psol/${PSOL_VERSION}.tar.gz \
&& tar -xzf ${PSOL_VERSION}.tar.gz

RUN cd /openresty-${OPENRESTY_VERSION} \
&& git clone https://github.com/FRiCKLE/ngx_cache_purge.git ngx_cache_purge-2.3 \
&& git clone https://github.com/vozlt/nginx-module-vts.git \
&& git clone https://github.com/google/ngx_brotli

RUN cd /openresty-${OPENRESTY_VERSION}/ngx_brotli && git submodule update --init

RUN cd /openresty-${OPENRESTY_VERSION} \
&& /openresty-${OPENRESTY_VERSION}/configure \
--add-module=/openresty-${OPENRESTY_VERSION}/incubator-pagespeed-ngx-${NPS_VERSION} \
--add-module=/openresty-${OPENRESTY_VERSION}/ngx_cache_purge-2.3 \
--add-module=/openresty-${OPENRESTY_VERSION}/nginx-module-vts \
--add-module=/openresty-${OPENRESTY_VERSION}/ngx_brotli \
--with-http_stub_status_module \
--with-http_v2_module --with-openssl=/openresty-${OPENRESTY_VERSION}/openssl-${OPEN_SSL} \
--with-ipv6 \
--with-http_realip_module \
&& /usr/bin/make && /usr/bin/make install

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log \
	&& ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log

RUN ln -s /usr/local/openresty/nginx/sbin/nginx /usr/bin/nginx
RUN ln -s /usr/local/openresty/nginx/conf /etc/nginx

RUN rm -rf /openresty-${OPENRESTY_VERSION}
RUN rm -rf /openresty-${OPENRESTY_VERSION}.tar.gz

RUN set -ex; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
	tar -xzf wordpress.tar.gz -C /var; \
	rm wordpress.tar.gz; \
    mv /var/wordpress /var/www; \
	chown -R www-data:www-data /var/www;


RUN rmdir /var/www/html && mv /var/www/wordpress /var/www/html
RUN echo '#!/bin/bash\n/usr/local/openresty/nginx/sbin/nginx -g "daemon off;" &\nphp-fpm --nodaemonize &\nwhile true; do sleep 1d; done' > /usr/bin/init.sh
RUN chmod +x /usr/bin/init.sh

EXPOSE 80 443
WORKDIR /var/www/html
CMD ["/usr/bin/init.sh"]
