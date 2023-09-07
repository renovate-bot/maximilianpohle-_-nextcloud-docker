ARG NEXTCLOUD_VERSION

FROM nextcloud:$NEXTCLOUD_VERSION

RUN set -ex; \
    apt-get update; \
    apt-get install -y ffmpeg imagemagick ghostscript; \
    apt-get clean
