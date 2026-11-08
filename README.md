# Asterisk call-center prototype

Прототип call-центра на **Asterisk 22 LTS, собранном из исходников в Docker**. Без FreePBX и других панелей: всё настроено руками в конфигах.

- **SIP-транк** к провайдеру: входящие опознаются по IP, исходящие проходят digest-авторизацию (401 → повторный INVITE с Authorization)
- **Dialplan**: входящий DID → проверка рабочего времени → IVR; исходящие через транк по префиксу 9
- **IVR**: 1 — продажи, 2 — поддержка, 0 — оператор, 9 — повтор меню; обработка неверного ввода и тишины, после 3 попыток прощание
- **Очереди** `sales` (rrmemory) и `support` (leastrecent, резервный агент с penalty), MOH, периодические объявления, пауза агентов
- **CDR и queue_log** пишутся в `./logs`

Провайдер и агенты сделаны на **SIPp** — так весь стенд поднимается одной командой и проверяется без живых телефонов. Подключить настоящий софтфон тоже можно (номер 103).

## Схема

```
                         SIP-транк (UDP 5060)
 carrier (SIPp)  ───────────────────────────────►  asterisk 22
 172.30.0.20       входящие на DID 74951234567      172.30.0.10
                 ◄───────────────────────────────    │  PJSIP, IVR, app_queue
                   исходящие 9XXXXXXXXXXX            │
                   (401 + digest)                    │  REGISTER + INVITE
                                                     ▼
                                            agents (SIPp) 172.30.0.31
                                            101, 102 — автоответ
                                            103 — живой софтфон (опционально)
```

## Быстрый старт

Нужны Docker с Compose v2 и `make`.

```bash
make up          # .env создаётся из .env.example; первая сборка Asterisk ~10-15 минут
make status      # транк, агенты 101/102 в contacts, обе очереди
make call-sales  # входящий звонок → IVR → нажать 1 → очередь sales → агент
```

`make help` покажет все команды.

## Сценарии проверки

| Команда | Что происходит | Что смотреть |
|---|---|---|
| `make call-sales` | DID → IVR → DTMF «1» → `sales` → агент 101/102 | `make queue-log`: ENTERQUEUE → CONNECT → COMPLETECALLER |
| `make call-support` | DTMF «2» → `support` → агент 102 (101 — резерв с penalty 1) | |
| `make call-operator` | DTMF «0» → Dial на 103 → не ответил → `support` | `make cli`: Dial → Queue |
| `make call-invalid` | DTMF «5» → «неверный выбор» → повтор меню → после 3 попыток прощание, BYE шлёт Asterisk | |
| `make call-silent` | ничего не нажато → таймаут WaitExten → повтор → прощание | |
| `make call-load` | 3 звонка одновременно, агентов 2 | третий ждёт в очереди (position 3) |
| `make pause-101` + `make call-sales` | агент на паузе не получает вызовы | вызов уходит на 102 |
| `make call-out` | исходящий 9 + номер через транк | INVITE → 401 → INVITE с Authorization → 180 → 200; номер АОН в P-Asserted-Identity |

Рабочее время задаётся в `.env` (`OFFICE_HOURS`). По умолчанию 24/7; с `09:00-18:00,mon-fri,*,*,Europe/Moscow` вне этого времени звонящий слышит «нерабочее время».

SIP-трассировка: `make sngrep` (sngrep внутри контейнера Asterisk) или `make logs`. Контейнер carrier выводит в лог все SIP-сообщения провайдера.

## Живой софтфон (агент 103)

Сервер `172.30.0.10:5060` (OrbStack видит IP контейнеров напрямую) или `127.0.0.1:5060` (Docker Desktop), логин `103`, пароль `AGENT_PASSWORD` из `.env`, кодеки G.711 (PCMA/PCMU).

После регистрации 103 появляется в `support` и принимает звонки по `0` из IVR. Внутренние номера: 101–103, `2000` — IVR, `2001` / `2002` — очереди напрямую, `600` — эхо-тест, `*46` / `*47` — пауза агента / снятие с паузы, `9` + номер — исходящий через транк.

## Структура

```
asterisk/
  Dockerfile              3 стадии: сборка из исходников → синтез подсказок IVR → runtime
  entrypoint.sh           рендер *.conf.tmpl из .env (envsubst по явному списку) и запуск
  config/
    pjsip.conf.tmpl       транспорт, транк (endpoint/aor/auth/identify), агенты на шаблонах
    extensions.conf.tmpl  from-trunk, after-hours, ivr-main, queue-route, from-internal
    queues.conf           sales, support, общий шаблон очереди
    modules.conf          autoload = no, явный список модулей
    indications.conf      тоны КПВ/занято для RU
    cdr.conf, rtp.conf, musiconhold.conf, logger.conf ...
  prompts/
    prompts.txt           тексты подсказок IVR → espeak-ng → wav 8 кГц при сборке
sipp/
  Dockerfile              SIPp 3.8 из исходников с PCAP (RTP, RFC 4733 DTMF)
  carrier.sh, agents.sh   запуск провайдера и агентов
  scenarios/              uac_inbound, uas_outbound, uas_agent, register
docker-compose.yml, Makefile, .env.example
```

## Решения, которые стоит пояснить

- **Asterisk из исходников, multi-stage.** В runtime-образ попадают только бинарники, модули и звуки, без компилятора. `BUILD_NATIVE` выключен, поэтому образ собирается одинаково на amd64 и arm64 (Apple Silicon). Звуки и MOH в ulaw: при G.711 не нужно транскодирование.
- **`modules.conf` с `autoload = no`.** Загружается около 60 модулей вместо нескольких сотен: старт быстрее, лог чистый, меньше поверхность атаки.
- **Транк.** Провайдер опознаётся по IP (`identify`), неизвестные адреса отбиваются (в `endpoint_identifier_order` нет `anonymous`). В From уходит логин транка, номер АОН — в `P-Asserted-Identity`. `send_connected_line = no`: без этой опции Asterisk при ответе агента слал провайдеру re-INVITE с новым PAI, и SIPp-провайдер обрывал вызов. Многие реальные операторы ведут себя так же. Блок для провайдера с регистрацией есть в `pjsip.conf.tmpl` в комментарии.
- **Очереди.** `ringinuse = no` + `device_state_busy_at = 1`: агент в разговоре не получает второй вызов. `joinempty` / `leavewhenempty`: если доступных агентов нет, звонящий не висит в пустой очереди. Объявления только своими русскими подсказками, без смеси со штатными английскими.
- **Секреты** только в `.env` (в `.gitignore`), в конфигах плейсхолдеры. Подстановка envsubst идёт по явному списку переменных, поэтому `${EXTEN}` и другие переменные диалплана не затираются.

## Что упрощено (это прототип)

- Подсказки IVR синтезированы espeak-ng. В продакшене их заменяют студийными записями с теми же именами файлов в `sounds/custom/`.
- Конфиги статические. Следующий шаг — realtime через ODBC (PJSIP, очереди и CDR в MariaDB) и AMI/ARI для панели оператора.
- Без TLS/SRTP и fail2ban. Порты наружу открыты только на `127.0.0.1`.
