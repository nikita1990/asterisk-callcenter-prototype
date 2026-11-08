# syntax=docker/dockerfile:1
#
# SIPp 3.8, собранный из исходников с PCAP (нужен для RTP и DTMF).
# Один образ — два сервиса в docker-compose:
#  carrier — "провайдер": принимает исходящие от Asterisk (digest-авторизация),
#            по запросу звонит на DID и нажимает цифру в IVR (make call-sales и т.д.)
#  agents  — агенты 101/102: регистрируются на Asterisk и автоматически отвечают

ARG DEBIAN_RELEASE=bookworm

FROM debian:${DEBIAN_RELEASE}-slim AS build
ARG SIPP_VERSION=v3.8.0
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates \
        libpcap-dev libncurses-dev libssl-dev libgsl-dev \
    && rm -rf /var/lib/apt/lists/*
# pugixml — git-сабмодуль, без --recurse-submodules cmake падает
RUN git clone --depth 1 --branch "${SIPP_VERSION}" --recurse-submodules --shallow-submodules \
        https://github.com/SIPp/sipp.git /usr/src/sipp
WORKDIR /usr/src/sipp
RUN cmake . -DUSE_PCAP=1 -DUSE_GSL=1 -DUSE_SSL=1 && make -j"$(nproc)" sipp

FROM debian:${DEBIAN_RELEASE}-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpcap0.8 libncurses6 libssl3 libgsl27 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/src/sipp/sipp /usr/local/bin/sipp
COPY --from=build /usr/src/sipp/pcap /opt/sipp/pcap
COPY scenarios/ /opt/sipp/
COPY carrier.sh agents.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/carrier.sh /usr/local/bin/agents.sh
WORKDIR /opt/sipp
EXPOSE 5060/udp
# команда (carrier.sh / agents.sh) задаётся в docker-compose.yml
