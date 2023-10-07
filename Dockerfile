ARG NEXTCLOUD_VERSION

FROM nextcloud:apache as builder

# Build and install dlib on builder
RUN apt-get update ; \
    apt-get install -y build-essential wget cmake libx11-dev libopenblas-dev shtool

ARG DLIB_VERSION=v19.24.2
RUN cd; \
    wget -c -q https://github.com/davisking/dlib/archive/${DLIB_VERSION}.tar.gz \
    && tar xf ${DLIB_VERSION}.tar.gz \
    && mv dlib-* dlib \
    && cd dlib/dlib \
    && mkdir build \
    && cd build \
    && cmake -DBUILD_SHARED_LIBS=ON .. \
    && make \
    && make install

# Build and install PDLib on builder
ENV PDLIB_VERSION=v1.1.0
RUN cd; \
    wget -c -q https://github.com/goodspb/pdlib/archive/refs/tags/${PDLIB_VERSION}.tar.gz \
    && tar xvzf ${PDLIB_VERSION}.tar.gz \
    && mv pdlib-* pdlib \
    && cd pdlib \
    && phpize \
    && ./configure \
    && make \
    && make install

RUN cp $(php-config --extension-dir)/pdlib.so /tmp/pdlib.so

# Enable PDlib on builder
# If necesary take the php settings folder uncommenting the next line
# RUN php -i | grep "Scan this dir for additional .ini files"
RUN echo "extension=pdlib.so" > /usr/local/etc/php/conf.d/pdlib.ini

FROM nextcloud:$NEXTCLOUD_VERSION

ENV NEXTCLOUD_UPDATE=1
ENV PHP_MEMORY_LIMIT=1G

RUN set -ex; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libbz2-dev \
        libc-client-dev \
        libkrb5-dev \
        libsmbclient-dev \
        ffmpeg imagemagick ghostscript libopenblas-dev supervisor libopenblas-base \
    ; \
    \
    docker-php-ext-install \
        bz2 \
    ; \

# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
;

# Install dlib and PDlib to image
COPY --from=builder /usr/local/lib/libdlib.so* /usr/local/lib/

# If is necesary take the php extention folder uncommenting the next line
#RUN php -i # | grep extension_dir
COPY --from=builder /tmp/pdlib.so /tmp/pdlib.so
RUN mv /tmp/pdlib.so $(php-config --extension-dir)/

# Enable PDlib on final image
RUN echo "extension=pdlib.so" > /usr/local/etc/php/conf.d/pdlib.ini

# Set ENV varaiable for PHP memory limits (can be adjusted in docker)
RUN echo "memory_limit=${PHP_MEMORY_LIMIT}" > /usr/local/etc/php/conf.d/memory-limit.ini
RUN echo '*/30 * * * * php -f /var/www/html/occ face:background_job -t 900' >> /var/spool/cron/crontabs/www-data
RUN sed -i -e '/^<VirtualHost/,/<\/VirtualHost>/ { /<\/VirtualHost>/ i\Header always set Strict-Transport-Security "max-age=15552000; includeSubDomain"' -e '}' /etc/apache2/sites-enabled/000-default.conf

RUN useradd -ms /bin/bash -u 1000 -s /sbin/nologin nextcloud
RUN mkdir -p /var/log/supervisord && \
    mkdir -p /var/run/supervisord && \
    chown -R 1000 /var/log/supervisord && \
    chown -R 1000 /var/run/supervisord
USER nextcloud
COPY supervisord.conf /
CMD ["/usr/bin/supervisord", "-c", "/supervisord.conf"]
