#!/bin/sh
# Постоянно работающий UAS провайдера: принимает исходящие вызовы от Asterisk.
# Логин/пароль транка — те же, что Asterisk берёт из .env.
# SIP-сообщения UAS пишутся в лог контейнера: docker compose logs -f carrier
set -eu
: "${TRUNK_USERNAME:?}" "${TRUNK_PASSWORD:?}"

# IP контейнера: из compose (SIPP_IP), иначе из /etc/hosts
IP="${SIPP_IP:-$(getent hosts "$(cat /etc/hostname)" | awk '{print $1; exit}')}"
mkdir -p /var/log/sipp
touch /var/log/sipp/uas_messages.log

# SIP-сообщения выводим в лог контейнера, сам SIPp — PID 1:
# упадёт SIPp — упадёт контейнер, и это сразу видно в `docker compose ps`.
# (sipp -bg не используем: он всегда возвращает код 99)
tail -F /var/log/sipp/uas_messages.log &

echo "carrier UAS listening on $IP:5060"
exec sipp -sf /opt/sipp/uas_outbound.xml -i "$IP" -p 5060 \
    -set trunk_user "$TRUNK_USERNAME" -set trunk_pass "$TRUNK_PASSWORD" \
    -nostdin \
    -trace_msg -message_file /var/log/sipp/uas_messages.log \
    -trace_err -error_file /var/log/sipp/uas_errors.log \
    > /dev/null
