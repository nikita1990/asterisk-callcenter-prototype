# Короткие команды для демо. Все звонки идут из контейнера carrier (SIPp) на DID.
SHELL := /bin/bash
-include .env
DC      := docker compose
AST     := $(DC) exec asterisk asterisk -rx
DID     := $(TRUNK_DID)
# UAC "провайдера": отдельный SIP-порт 5070 и RTP-порт 6100, чтобы не мешать UAS на 5060
UAC     := $(DC) exec carrier sipp -sf /opt/sipp/uac_inbound.xml \
           -i 172.30.0.20 -p 5070 -mi 172.30.0.20 -mp 6100 -s $(DID) -nostdin \
           -trace_err -error_file /var/log/sipp/uac_errors.log
TARGET  := 172.30.0.10:5060

.PHONY: help up down restart logs cli sngrep status reload \
        call-sales call-support call-operator call-invalid call-silent call-load call-out \
        pause-101 unpause-101 queue-log cdr

help:            ## список команд
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-15s %s\n", $$1, $$2}'

.env:
	cp .env.example .env

up: .env         ## собрать и запустить (первая сборка Asterisk ~10-15 мин)
	$(DC) up -d --build
	@$(DC) ps

down:            ## остановить
	$(DC) down

restart:         ## перезапустить контейнеры
	$(DC) restart

logs:            ## логи всех контейнеров
	$(DC) logs -f --tail=50

cli:             ## консоль Asterisk
	$(DC) exec asterisk asterisk -rvvv

sngrep:          ## SIP-трассировка внутри контейнера Asterisk
	$(DC) exec asterisk sngrep -d any

status:          ## транк, агенты, очереди
	@$(AST) "pjsip show endpoints"
	@$(AST) "pjsip show contacts"
	@$(AST) "queue show"

reload:          ## перечитать конфиги после правки в asterisk/config
	$(DC) exec asterisk entrypoint.sh render
	$(AST) "core reload"

call-sales:      ## входящий на DID -> IVR, нажать 1 -> очередь sales
	$(UAC) -set digits 1 -set wait_ms 4000 -set hold_ms 20000 -m 1 $(TARGET)

call-support:    ## входящий -> IVR, нажать 2 -> очередь support
	$(UAC) -set digits 2 -set wait_ms 4000 -set hold_ms 20000 -m 1 $(TARGET)

call-operator:   ## входящий -> IVR, нажать 0 -> оператор 103, не ответил -> support
	$(UAC) -set digits 0 -set wait_ms 4000 -set hold_ms 40000 -m 1 $(TARGET)

call-invalid:    ## неверная цифра 5: "неверный выбор", повтор меню, после 3 попыток Asterisk кладёт трубку
	$(UAC) -set digits 5 -set wait_ms 4000 -set hold_ms 70000 -m 1 $(TARGET)

call-silent:     ## ничего не нажимать: таймаут меню -> повтор -> прощание
	$(UAC) -set digits '' -set wait_ms 4000 -set hold_ms 70000 -m 1 $(TARGET)

call-load:       ## 3 одновременных звонка в sales при 2 агентах: третий ждёт в очереди
	$(UAC) -set digits 1 -set wait_ms 4000 -set hold_ms 20000 -m 3 -r 3 -l 3 $(TARGET)

call-out:        ## исходящий через транк (9 + номер): 401 -> digest -> 200
	$(AST) "channel originate Local/979001234567@from-internal application Playback demo-congrats"
	@sleep 12; $(DC) logs --since 30s --no-log-prefix carrier | grep -E 'INVITE sip|SIP/2.0 [0-9]+|Authorization|P-Asserted|BYE sip' || true

pause-101:       ## поставить агента 101 на паузу во всех очередях
	$(AST) "queue pause member PJSIP/101"

unpause-101:     ## снять агента 101 с паузы
	$(AST) "queue unpause member PJSIP/101"

queue-log:       ## события очередей
	@cat logs/queue_log

cdr:             ## последние CDR
	@tail -n 10 logs/cdr-csv/Master.csv
