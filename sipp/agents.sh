#!/bin/sh
# Агенты call-центра на SIPp:
#  - UAS на :5060 отвечает на вызовы для всех агентов (180 -> 200 -> "говорит" G.711 -> BYE)
#  - каждые REG_INTERVAL секунд агенты перерегистрируются с порта :5070,
#    в Contact указывают :5060 (поэтому у 101/102 rewrite_contact = no)
set -eu
: "${ASTERISK_HOST:?}" "${AGENT_PASSWORD:?}"
AGENTS="${AGENTS:-101 102}"
REG_EXPIRES="${REG_EXPIRES:-300}"
REG_INTERVAL="${REG_INTERVAL:-240}"
# IP контейнера: из compose (SIPP_IP), иначе из /etc/hosts
IP="${SIPP_IP:-$(getent hosts "$(cat /etc/hostname)" | awk '{print $1; exit}')}"
mkdir -p /var/log/sipp

# UAS в фоне (sipp -bg не используем: он всегда возвращает код 99)
sipp -sf /opt/sipp/uas_agent.xml -i "$IP" -p 5060 -nostdin \
    -trace_msg -message_file /var/log/sipp/agent_messages.log \
    -trace_err -error_file /var/log/sipp/agent_errors.log \
    > /dev/null 2>&1 &
UAS_PID=$!
echo "agents UAS listening on $IP:5060 (pid $UAS_PID)"

register() {
    sipp -sf /opt/sipp/register.xml -i "$IP" -p 5070 -m 1 -nostdin \
        -s "$1" -au "$1" -ap "$AGENT_PASSWORD" \
        -set contact_port 5060 -set expires "$REG_EXPIRES" \
        -timeout 10 -timeout_error \
        "$ASTERISK_HOST:5060" > /dev/null 2>&1
}

while true; do
    # UAS умер — выходим, Docker перезапустит контейнер (restart: unless-stopped)
    kill -0 "$UAS_PID" 2>/dev/null || { echo "agent UAS died"; exit 1; }
    for a in $AGENTS; do
        if register "$a"; then
            echo "$(date '+%F %T') agent $a registered (expires ${REG_EXPIRES}s)"
        else
            echo "$(date '+%F %T') agent $a registration FAILED, retry in 5s"
            sleep 5
            continue 2
        fi
    done
    sleep "$REG_INTERVAL"
done
