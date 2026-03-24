# mig-litellm-a100-lab

Bare-metal LLMOps lab for a single NVIDIA A100 40GB using MIG, Hugging Face TGI, LiteLLM, Open WebUI, Prometheus, Grafana, and a custom context-guard policy layer.

Русская версия: [README.ru.md](README.ru.md)

## What this project demonstrates

- Split one physical NVIDIA A100 40GB into multiple isolated MIG slices.
- Run several LLM endpoints on independent MIG slices on the same GPU.
- Expose all model tiers behind one OpenAI-compatible API endpoint.
- Add a policy layer (`context-guard`) in front of LiteLLM to auto-recover from context window overflow.
- Observe GPU, MIG, request, latency, fallback, reset, and load metrics in Prometheus and Grafana.
- Prove MIG isolation with an OOM demo on one slice while the other slices stay healthy.
- Generate synthetic text traffic to watch RPS and p95/p99 latency in Grafana.

## Current architecture

Request path:

`Browser / Open WebUI -> context-guard -> LiteLLM Proxy -> TGI -> MIG slice on A100`

Model tiers:

- `general-chat` -> `tgi-general` -> `MIG 3g.20gb`
- `fast-chat` -> `tgi-fast` -> `MIG 2g.10gb`
- `tiny-chat` -> `tgi-tiny` -> `MIG 1g.5gb`
- `stress-worker` / OOM demo -> separate `MIG 1g.5gb`

Monitoring path:

- `dcgm-exporter -> Prometheus -> Grafana`
- `context-guard -> Prometheus -> Grafana`
- `LiteLLM metrics -> Prometheus -> Grafana`
- `TGI metrics -> Prometheus -> Grafana`

More details: [docs/architecture.md](docs/architecture.md) | [docs/architecture.ru.md](docs/architecture.ru.md)

## Key features added in the current version

- **Context recovery for all model tiers**: if a prompt exceeds the context window, `context-guard` retries with a compact prompt policy adapted to `general-chat`, `fast-chat`, or `tiny-chat`.
- **Prometheus metrics from multiple layers**: GPU/MIG telemetry, policy-layer metrics, LiteLLM proxy metrics, and TGI inference metrics.
- **Grafana dashboards**:
  - `LLMOps Overview`
  - `MIG Visual Layout`
- **OOM isolation demo**: force memory exhaustion on one MIG slice and show other model servers remain healthy.
- **Synthetic text load generator**: simulate 10 / 20 / 50 users or custom concurrency to observe RPS and p95/p99.

## Default MIG layout

- `3g.20gb` -> `general-chat`
- `2g.10gb` -> `fast-chat`
- `1g.5gb` -> `tiny-chat`
- `1g.5gb` -> `stress-worker`

## Default model set

- `Qwen/Qwen2.5-3B-Instruct`
- `Qwen/Qwen2.5-1.5B-Instruct`
- `Qwen/Qwen2.5-0.5B-Instruct`

## Repository layout

- `scripts/` host bootstrap, MIG setup, validation, load tools, cleanup
- `compose/docker-compose.yml` stack definition
- `config/` LiteLLM, Prometheus, Grafana, dashboards
- `services/context_guard/` policy layer and custom metrics exporter
- `workloads/stress-worker/` MIG OOM / memory pressure demo
- `workloads/text-load/` synthetic LLM request generator
- `docs/` architecture, demo flow, Eraser prompt
- `tests/` helper checks

## Fast path on a rented server

```bash
git clone https://github.com/AlexeySmirnov74/mig-litellm-nvidia-a100-lab
cd mig-litellm-a100-lab
cp .env.example .env
# fill HF_TOKEN if needed
sudo bash scripts/00_host_prereqs.sh
sudo bash scripts/01_enable_mig.sh
sudo bash scripts/02_create_layout.sh
sudo bash scripts/03_export_env.sh
sudo bash scripts/04_validate_host.sh
bash scripts/05_start_stack.sh
bash scripts/06_demo_queries.sh
```

Then open:

- Open WebUI: `http://SERVER_IP:3000`
- LiteLLM API: `http://SERVER_IP:4000`
- context-guard API: `http://SERVER_IP:4010`
- Grafana: `http://SERVER_IP:3001`
- Prometheus: `http://SERVER_IP:9090`

## Typical demo flow

1. Open Grafana and keep `LLMOps Overview` and `MIG Visual Layout` visible.
2. Ask the same prompt to `general-chat`, `fast-chat`, and `tiny-chat` in Open WebUI.
3. Start the OOM demo on the dedicated stress slice.
4. Watch one `1g.5gb` slice move into warning / critical memory pressure while the others remain healthy.
5. Keep sending prompts to `general-chat` and `fast-chat` to show MIG isolation.
6. Run the text load generator with 10 / 20 / 50 users and observe RPS and p95/p99 in Grafana.
7. Optionally trigger long-history chats to demonstrate automatic context reset handling.

## Useful scripts

- `scripts/05_start_stack.sh` - start the main stack
- `scripts/06_demo_queries.sh` - basic smoke queries
- `scripts/07_start_stress.sh` - start the OOM / memory pressure demo
- `scripts/08_stop_stress.sh` - stop the OOM demo
- `scripts/09_start_text_load.sh` - start configurable synthetic user traffic
- `scripts/10_stop_text_load.sh` - stop text load generation
- `scripts/99_cleanup.sh` - full cleanup

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

## Important notes

- The easiest path is to rent a server image that already has a working NVIDIA driver and `nvidia-smi` available.
- The bootstrap script installs Docker, Docker Compose plugin, and NVIDIA Container Toolkit. It does **not** force-install a provider-specific GPU driver.
- Some providers require a reboot after enabling MIG.
- `tiny-chat` is intentionally constrained and may auto-reset context more often than the other tiers.
- Very fast Prometheus / Grafana refresh intervals are great for demos, but heavier than typical production defaults.

## Docs

- English architecture: [docs/architecture.md](docs/architecture.md)
- Russian architecture: [docs/architecture.ru.md](docs/architecture.ru.md)

## Screenshots

[https://github.com/AlexeySmirnov74/mig-litellm-nvidia-a100-lab/tree/main/screenshots](https://github.com/AlexeySmirnov74/mig-litellm-nvidia-a100-lab/tree/main/screenshots)

