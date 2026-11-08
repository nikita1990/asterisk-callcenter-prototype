# syntax=docker/dockerfile:1
#
# Asterisk 22 LTS, собранный из исходников.
# Три стадии: build (компиляция) -> prompts (голосовые подсказки IVR) -> runtime (только нужное для работы).

ARG DEBIAN_RELEASE=bookworm

############################ 1. build ############################
FROM debian:${DEBIAN_RELEASE}-slim AS build

ARG ASTERISK_VERSION=22.12.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl bzip2 patch pkg-config python3 \
        libedit-dev libjansson-dev libxml2-dev libsqlite3-dev uuid-dev \
        libssl-dev libncurses-dev libcurl4-openssl-dev libsrtp2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN curl -fsSL "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VERSION}.tar.gz" \
        | tar xz

WORKDIR /usr/src/asterisk-${ASTERISK_VERSION}

# pjproject собирается в комплекте с Asterisk (рекомендованный путь для res_pjsip)
RUN ./configure \
        --prefix=/usr --sysconfdir=/etc --localstatedir=/var --libdir=/usr/lib \
        --with-pjproject-bundled \
    > /dev/null

# Только нужное: без BUILD_NATIVE (переносимость между amd64/arm64),
# звуки en в ulaw + музыка на удержании в ulaw (G.711 без транскодирования).
RUN make menuselect.makeopts \
    && menuselect/menuselect \
        --disable BUILD_NATIVE \
        --disable-category MENUSELECT_CORE_SOUNDS \
        --disable-category MENUSELECT_MOH \
        --disable-category MENUSELECT_EXTRA_SOUNDS \
        --enable CORE-SOUNDS-EN-ULAW \
        --enable MOH-OPSOUND-ULAW \
        --enable app_queue \
        --enable res_pjsip \
        menuselect.makeopts

RUN make -j"$(nproc)" \
    && make install DESTDIR=/opt/staging \
    && rm -rf /opt/staging/usr/include /opt/staging/var/run

############################ 2. prompts ############################
# Подсказки IVR синтезируются из текста (prompts/prompts.txt) при сборке.
# Для продакшена их заменяют студийными записями с теми же именами файлов.
FROM debian:${DEBIAN_RELEASE}-slim AS prompts

RUN apt-get update && apt-get install -y --no-install-recommends espeak-ng sox \
    && rm -rf /var/lib/apt/lists/*

COPY prompts/ /src/
RUN sh /src/gen-prompts.sh /src/prompts.txt /prompts

############################ 3. runtime ############################
FROM debian:${DEBIAN_RELEASE}-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        libedit2 libjansson4 libxml2 libsqlite3-0 libuuid1 libssl3 \
        libncurses6 libcurl4 libsrtp2-1 \
        gettext-base procps sngrep \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r asterisk && useradd -r -g asterisk -d /var/lib/asterisk asterisk

COPY --from=build   /opt/staging/  /
COPY --from=prompts /prompts/      /var/lib/asterisk/sounds/custom/
COPY entrypoint.sh  /usr/local/bin/entrypoint.sh

RUN ldconfig \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /etc/asterisk /var/log/asterisk /var/spool/asterisk /var/run/asterisk \
    && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk \
                                  /var/spool/asterisk /var/run/asterisk

EXPOSE 5060/udp 10000-10099/udp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
