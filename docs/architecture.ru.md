# Архитектура

English version: [architecture.md](architecture.md)

## Общая схема

Основной путь запроса:

`Browser / Open WebUI -> context-guard -> LiteLLM Proxy -> TGI -> MIG slice on A100`

### Привязка моделей

- `general-chat` -> `tgi-general` -> `MIG 3g.20gb`
- `fast-chat` -> `tgi-fast` -> `MIG 2g.10gb`
- `tiny-chat` -> `tgi-tiny` -> `MIG 1g.5gb`
- `stress-worker` / OOM demo -> отдельный `MIG 1g.5gb`

## Зачем нужен `context-guard`

`context-guard` — это лёгкий policy-layer перед LiteLLM.

Его задачи:

- принимать OpenAI-compatible chat-запросы из Open WebUI или test-клиентов
- проксировать обычный трафик в LiteLLM
- ловить context window overflow для всех model tier
- повторять запрос с компактной policy в зависимости от tier модели
- отдавать собственные Prometheus-метрики по request rate, latency, context reset, fallback failure и in-flight requests

## Путь мониторинга

- `dcgm-exporter -> Prometheus -> Grafana`
- `context-guard -> Prometheus -> Grafana`
- `LiteLLM metrics -> Prometheus -> Grafana`
- `TGI metrics -> Prometheus -> Grafana`

## Дашборды

### LLMOps Overview

Показывает service-level и inference-level сигналы:

- RPS
- p95 / p99 latency
- error rate
- in-flight requests
- context reset и fallback failure
- давление по памяти GPU
- таймлайн OOM risk

### MIG Visual Layout

Показывает уровень отдельных slice:

- occupancy percentage по каждому MIG slice
- used memory по каждому slice
- GPU utilization по каждому slice
- state timeline со статусами free / busy / near-OOM

## Демо нагрузки и отказа

### Text load demo

`workloads/text-load/` имитирует конкурентных пользователей, чтобы нагружать API и показывать:

- request rate
- latency
- mix моделей
- reset / failures

### OOM isolation demo

`workloads/stress-worker/` по шагам аллоцирует память на отдельном stress slice до OOM или allocator failure.

Ожидаемая картина:

- stress slice уходит в high memory pressure и затем в OOM
- stress container завершается
- `general-chat`, `fast-chat` и `tiny-chat` на других MIG slice остаются живыми

## Практический итог

Этот lab показывает, что одна физическая A100 может одновременно держать несколько изолированных LLM serving tier, policy-layer, стек наблюдаемости и controlled failure demo, при этом сохраняя изоляцию между slice.
