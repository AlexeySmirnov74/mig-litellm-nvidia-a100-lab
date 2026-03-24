# Architecture

Russian version: [architecture.ru.md](architecture.ru.md)

## High-level flow

Main request path:

`Browser / Open WebUI -> context-guard -> LiteLLM Proxy -> TGI -> MIG slice on A100`

### Model mapping

- `general-chat` -> `tgi-general` -> `MIG 3g.20gb`
- `fast-chat` -> `tgi-fast` -> `MIG 2g.10gb`
- `tiny-chat` -> `tgi-tiny` -> `MIG 1g.5gb`
- `stress-worker` / OOM demo -> dedicated `MIG 1g.5gb`

## Why `context-guard` exists

`context-guard` is a lightweight policy layer placed in front of LiteLLM.

Its responsibilities:

- receive OpenAI-compatible chat requests from Open WebUI or test clients
- forward normal traffic to LiteLLM
- catch context window overflow errors for all model tiers
- retry with a compressed request policy adapted to each model tier
- expose its own Prometheus metrics for request rate, latency, context resets, fallback failures, and in-flight requests

## Monitoring flow

- `dcgm-exporter -> Prometheus -> Grafana`
- `context-guard -> Prometheus -> Grafana`
- `LiteLLM metrics -> Prometheus -> Grafana`
- `TGI metrics -> Prometheus -> Grafana`

## Dashboards

### LLMOps Overview

Focuses on service-level and inference-level signals:

- RPS
- p95 / p99 latency
- error rate
- in-flight requests
- context resets and fallback failures
- GPU memory pressure
- OOM risk timeline

### MIG Visual Layout

Focuses on slice-level visibility:

- occupancy percentage per MIG slice
- used memory per slice
- GPU utilization per slice
- state timeline showing free / busy / near-OOM periods

## Load and failure demos

### Text load demo

`workloads/text-load/` simulates concurrent users against the API to drive:

- request rate
- latency
- model mix
- resets / failures

### OOM isolation demo

`workloads/stress-worker/` allocates memory step-by-step on the dedicated stress slice until OOM or allocator failure.

Expected observation:

- the stress slice goes into high memory pressure and eventually OOM
- the stress container exits
- `general-chat`, `fast-chat`, and `tiny-chat` on other MIG slices remain healthy

## Practical summary

This lab demonstrates that one physical A100 can host multiple isolated LLM serving tiers, a policy layer, observability stack, and controlled failure demos while preserving slice-level isolation.
