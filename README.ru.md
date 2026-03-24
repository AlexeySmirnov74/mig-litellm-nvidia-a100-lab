# mig-litellm-a100-lab

Bare-metal LLMOps lab на одной NVIDIA A100 40GB с использованием MIG, Hugging Face TGI, LiteLLM, Open WebUI, Prometheus, Grafana и собственного policy-layer `context-guard`.

English version: [README.md](README.md)

## Что показывает проект

- Разделение одной физической NVIDIA A100 40GB на несколько изолированных MIG slice.
- Запуск нескольких LLM endpoint на независимых slice одной и той же GPU.
- Единый OpenAI-compatible API поверх всех model tier.
- Policy-layer `context-guard` перед LiteLLM для автоматического восстановления после переполнения context window.
- Наблюдаемость по GPU, MIG, latency, RPS, fallback, reset и synthetic load через Prometheus и Grafana.
- Демонстрацию MIG isolation через OOM на одном slice без падения соседних slice.
- Генерацию синтетической текстовой нагрузки, чтобы смотреть RPS и p95/p99 в Grafana.

## Текущая архитектура

Путь запросов:

`Browser / Open WebUI -> context-guard -> LiteLLM Proxy -> TGI -> MIG slice on A100`

Model tier:

- `general-chat` -> `tgi-general` -> `MIG 3g.20gb`
- `fast-chat` -> `tgi-fast` -> `MIG 2g.10gb`
- `tiny-chat` -> `tgi-tiny` -> `MIG 1g.5gb`
- `stress-worker` / OOM demo -> отдельный `MIG 1g.5gb`

Путь мониторинга:

- `dcgm-exporter -> Prometheus -> Grafana`
- `context-guard -> Prometheus -> Grafana`
- `LiteLLM metrics -> Prometheus -> Grafana`
- `TGI metrics -> Prometheus -> Grafana`

Подробности: [docs/architecture.ru.md](docs/architecture.ru.md) | [docs/architecture.md](docs/architecture.md)

## Что было добавлено в текущей версии

- **Context recovery для всех tier**: если запрос не помещается в окно контекста, `context-guard` повторяет его с compact-policy отдельно для `general-chat`, `fast-chat` и `tiny-chat`.
- **Метрики из нескольких слоёв**: GPU/MIG telemetry, policy-layer metrics, LiteLLM proxy metrics и TGI inference metrics.
- **Готовые Grafana dashboards**:
  - `LLMOps Overview`
  - `MIG Visual Layout`
- **OOM isolation demo**: принудительное переполнение памяти на одном MIG slice с сохранением работоспособности других model server.
- **Synthetic text load generator**: имитация 10 / 20 / 50 пользователей или своей конкуррентности для наблюдения за RPS и p95/p99.

## Базовая MIG-схема

- `3g.20gb` -> `general-chat`
- `2g.10gb` -> `fast-chat`
- `1g.5gb` -> `tiny-chat`
- `1g.5gb` -> `stress-worker`

## Набор моделей по умолчанию

- `Qwen/Qwen2.5-3B-Instruct`
- `Qwen/Qwen2.5-1.5B-Instruct`
- `Qwen/Qwen2.5-0.5B-Instruct`

## Структура репозитория

- `scripts/` - bootstrap хоста, настройка MIG, валидация, генераторы нагрузки, cleanup
- `compose/docker-compose.yml` - описание стека
- `config/` - LiteLLM, Prometheus, Grafana и dashboards
- `services/context_guard/` - policy-layer и собственный exporter метрик
- `workloads/stress-worker/` - OOM / memory pressure demo
- `workloads/text-load/` - генератор синтетических запросов к LLM
- `docs/` - архитектура, demo flow, prompt для Eraser
- `tests/` - вспомогательные проверки

## Быстрый запуск на арендованном сервере

```bash
git clone https://github.com/AlexeySmirnov74/mig-litellm-nvidia-a100-lab
cd mig-litellm-a100-lab
cp .env.example .env
# при необходимости заполни HF_TOKEN
sudo bash scripts/00_host_prereqs.sh
sudo bash scripts/01_enable_mig.sh
sudo bash scripts/02_create_layout.sh
sudo bash scripts/03_export_env.sh
sudo bash scripts/04_validate_host.sh
bash scripts/05_start_stack.sh
bash scripts/06_demo_queries.sh
```

Потом открыть:

- Open WebUI: `http://SERVER_IP:3000`
- LiteLLM API: `http://SERVER_IP:4000`
- context-guard API: `http://SERVER_IP:4010`
- Grafana: `http://SERVER_IP:3001`
- Prometheus: `http://SERVER_IP:9090`

## Типовой demo flow

1. Открыть Grafana и держать видимыми `LLMOps Overview` и `MIG Visual Layout`.
2. Отправить одинаковый prompt в `general-chat`, `fast-chat` и `tiny-chat` через Open WebUI.
3. Запустить OOM demo на выделенном stress slice.
4. Посмотреть, как один `1g.5gb` slice уходит в warning / critical по памяти, а остальные slice остаются живыми.
5. Продолжить отправлять запросы в `general-chat` и `fast-chat`, показывая MIG isolation.
6. Запустить text load generator на 10 / 20 / 50 пользователей и наблюдать RPS и p95/p99 в Grafana.
7. При желании показать обработку длинной истории чата и автоматический context reset.

## Полезные скрипты

- `scripts/05_start_stack.sh` - запуск основного стека
- `scripts/06_demo_queries.sh` - базовые smoke queries
- `scripts/07_start_stress.sh` - запуск OOM / memory pressure demo
- `scripts/08_stop_stress.sh` - остановка OOM demo
- `scripts/09_start_text_load.sh` - запуск синтетического текстового трафика
- `scripts/10_stop_text_load.sh` - остановка text load
- `scripts/99_cleanup.sh` - полный cleanup

## Make targets

```bash
make host
make mig
make up
make demo
make stress-on
make stress-off
make load USERS=20 DURATION=120 THINK=0.3 MODE=all TOKENS=64
make load-stop
make down
```

## Важные замечания

- Самый простой путь - арендовать сервер, где уже есть рабочий NVIDIA driver и `nvidia-smi`.
- Bootstrap-скрипт ставит Docker, Docker Compose plugin и NVIDIA Container Toolkit, но не делает provider-specific установку драйвера.
- У некоторых провайдеров после включения MIG требуется reboot.
- `tiny-chat` специально ограничена сильнее остальных tier и может чаще выполнять auto-reset контекста.
- Очень быстрые интервалы refresh для Prometheus / Grafana хороши для demo, но тяжелее обычных production default.

## Документация

- Архитектура EN: [docs/architecture.md](docs/architecture.md)
- Архитектура RU: [docs/architecture.ru.md](docs/architecture.ru.md)

## Screenshots

[https://github.com/AlexeySmirnov74/mig-litellm-nvidia-a100-lab/tree/main/screenshots](https://github.com/AlexeySmirnov74/mig-litellm-nvidia-a100-lab/tree/main/screenshots)



