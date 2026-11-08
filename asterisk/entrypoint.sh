#!/bin/sh
# Рендер конфигов и запуск Asterisk в foreground.
#
# /etc/asterisk-src  — конфиги из репозитория (монтируются read-only)
# /etc/asterisk      — то, что реально читает Asterisk
#
# *.conf       копируются как есть
# *.conf.tmpl  проходят через envsubst ТОЛЬКО по явному списку переменных,
#              чтобы не трогать переменные диалплана вроде ${EXTEN}.
set -eu

SRC=/etc/asterisk-src
DST=/etc/asterisk
VARS='${TRUNK_HOST} ${TRUNK_PORT} ${TRUNK_USERNAME} ${TRUNK_PASSWORD} ${TRUNK_DID} ${OUTBOUND_CALLERID} ${AGENT_PASSWORD} ${OFFICE_HOURS}'

render() {
    for f in "$SRC"/*.conf; do
        [ -e "$f" ] && cp "$f" "$DST/"
    done
    for t in "$SRC"/*.conf.tmpl; do
        [ -e "$t" ] || continue
        out="$DST/$(basename "$t" .tmpl)"
        envsubst "$VARS" < "$t" > "$out"
    done
    chown -R asterisk:asterisk "$DST"
}

prepare_dirs() {
    # ./logs смонтирован с хоста: создаём подпапки и отдаём их пользователю asterisk
    mkdir -p /var/log/asterisk/cdr-csv
    chown -R asterisk:asterisk /var/log/asterisk
}

: "${TRUNK_HOST:?}" "${TRUNK_USERNAME:?}" "${TRUNK_PASSWORD:?}" "${TRUNK_DID:?}" "${AGENT_PASSWORD:?}"
: "${TRUNK_PORT:=5060}" "${OUTBOUND_CALLERID:=$TRUNK_DID}" "${OFFICE_HOURS:=*,*,*,*}"
export TRUNK_PORT OUTBOUND_CALLERID OFFICE_HOURS

render

# `entrypoint.sh render` — только перерендерить конфиги в работающем контейнере (make reload)
if [ "${1:-}" = "render" ]; then
    echo "configs rendered into $DST"
    exit 0
fi

prepare_dirs
exec asterisk -f -U asterisk -G asterisk -vvv
