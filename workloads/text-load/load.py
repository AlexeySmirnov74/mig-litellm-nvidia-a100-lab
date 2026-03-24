import asyncio
import os
import random
import statistics
import time
from collections import Counter

import httpx


def env_int(name: str, default: int) -> int:
    v = os.getenv(name)
    return int(v) if v not in (None, "") else default


def env_float(name: str, default: float) -> float:
    v = os.getenv(name)
    return float(v) if v not in (None, "") else default


def env_str(name: str, default: str) -> str:
    v = os.getenv(name)
    return v if v not in (None, "") else default


API_BASE = env_str("LOAD_API_BASE", "http://context-guard:4010/v1")
API_KEY = env_str("LOAD_API_KEY", "dummy-local-key")
USERS = env_int("LOAD_USERS", 10)
DURATION_SEC = env_int("LOAD_DURATION_SEC", 120)
THINK_TIME_SEC = env_float("LOAD_THINK_TIME_SEC", 0.5)
TIMEOUT_SEC = env_float("LOAD_TIMEOUT_SEC", 120.0)
MODEL_MODE = env_str("LOAD_MODEL_MODE", "all").lower()
MAX_TOKENS = env_int("LOAD_MAX_TOKENS", 64)

PROMPTS = [
    "Объясни коротко что такое MIG в NVIDIA.",
    "Напиши 3 пункта почему изоляция GPU через MIG полезна.",
    "Скажи в одном абзаце чем fast-chat отличается от general-chat.",
    "Дай короткий ответ что такое p95 latency.",
    "Что увидит LLMOps инженер на дашборде при росте нагрузки?",
    "Опиши в 2-3 предложениях что происходит при OOM на одном MIG slice.",
    "Скажи как проверить что другие MIG slices не упали после OOM.",
    "В чем ценность Prometheus и Grafana для LLM inference?",
    "Чем отличается throughput от latency?",
    "Почему context reset policy полезен для маленьких моделей?"
]


def choose_model(counter: int) -> str:
    if MODEL_MODE == "general":
        return "general-chat"
    if MODEL_MODE == "fast":
        return "fast-chat"
    if MODEL_MODE == "tiny":
        return "tiny-chat"
    models = ["general-chat", "fast-chat", "tiny-chat"]
    return models[counter % len(models)]


def percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    idx = max(0, min(len(values) - 1, int(round((p / 100.0) * (len(values) - 1)))))
    return values[idx]


async def user_loop(user_id: int, stop_at: float, stats: dict, lock: asyncio.Lock) -> None:
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=TIMEOUT_SEC) as client:
        req_num = 0
        while time.time() < stop_at:
            model = choose_model(req_num + user_id)
            prompt = random.choice(PROMPTS)

            payload = {
                "model": model,
                "messages": [
                    {"role": "user", "content": f"[user={user_id} req={req_num}] {prompt}"}
                ],
                "max_tokens": MAX_TOKENS,
                "temperature": 0.2,
                "stream": False
            }

            started = time.perf_counter()
            status_label = "ok"

            try:
                resp = await client.post(f"{API_BASE}/chat/completions", headers=headers, json=payload)
                latency = time.perf_counter() - started

                if resp.status_code == 200:
                    status_label = "ok"
                else:
                    status_label = f"http_{resp.status_code}"

            except Exception as e:
                latency = time.perf_counter() - started
                status_label = f"exc_{type(e).__name__}"

            async with lock:
                stats["latencies"].append(latency)
                stats["status_counts"][status_label] += 1
                stats["model_counts"][model] += 1
                stats["requests_total"] += 1

            req_num += 1
            if THINK_TIME_SEC > 0:
                await asyncio.sleep(THINK_TIME_SEC)


async def periodic_report(started_at: float, stats: dict, lock: asyncio.Lock, stop_at: float) -> None:
    last_total = 0
    last_time = started_at

    while time.time() < stop_at:
        await asyncio.sleep(5)

        async with lock:
            total = stats["requests_total"]
            lats = list(stats["latencies"])
            statuses = dict(stats["status_counts"])
            models = dict(stats["model_counts"])

        now = time.time()
        delta_t = max(now - last_time, 0.001)
        delta_req = total - last_total
        current_rps = delta_req / delta_t

        p50 = percentile(lats, 50) if lats else 0.0
        p95 = percentile(lats, 95) if lats else 0.0
        p99 = percentile(lats, 99) if lats else 0.0

        print(
            f"[load] total={total} "
            f"rps_now={current_rps:.2f} "
            f"p50={p50:.3f}s p95={p95:.3f}s p99={p99:.3f}s "
            f"statuses={statuses} models={models}",
            flush=True,
        )

        last_total = total
        last_time = now


async def main() -> None:
    started_at = time.time()
    stop_at = started_at + DURATION_SEC

    print("=" * 80, flush=True)
    print("Starting text load test", flush=True)
    print(f"API_BASE={API_BASE}", flush=True)
    print(f"USERS={USERS}", flush=True)
    print(f"DURATION_SEC={DURATION_SEC}", flush=True)
    print(f"THINK_TIME_SEC={THINK_TIME_SEC}", flush=True)
    print(f"MODEL_MODE={MODEL_MODE}", flush=True)
    print(f"MAX_TOKENS={MAX_TOKENS}", flush=True)
    print("=" * 80, flush=True)

    stats = {
        "latencies": [],
        "status_counts": Counter(),
        "model_counts": Counter(),
        "requests_total": 0,
    }
    lock = asyncio.Lock()

    reporter = asyncio.create_task(periodic_report(started_at, stats, lock, stop_at))
    workers = [
        asyncio.create_task(user_loop(user_id=i, stop_at=stop_at, stats=stats, lock=lock))
        for i in range(USERS)
    ]

    await asyncio.gather(*workers)
    await reporter

    async with lock:
        lats = list(stats["latencies"])
        statuses = dict(stats["status_counts"])
        models = dict(stats["model_counts"])
        total = stats["requests_total"]

    elapsed = max(time.time() - started_at, 0.001)
    avg = statistics.mean(lats) if lats else 0.0
    p50 = percentile(lats, 50) if lats else 0.0
    p95 = percentile(lats, 95) if lats else 0.0
    p99 = percentile(lats, 99) if lats else 0.0
    rps = total / elapsed

    print("\n" + "=" * 80, flush=True)
    print("FINAL LOAD TEST SUMMARY", flush=True)
    print(f"elapsed={elapsed:.1f}s", flush=True)
    print(f"total_requests={total}", flush=True)
    print(f"avg_rps={rps:.2f}", flush=True)
    print(f"avg_latency={avg:.3f}s", flush=True)
    print(f"p50={p50:.3f}s", flush=True)
    print(f"p95={p95:.3f}s", flush=True)
    print(f"p99={p99:.3f}s", flush=True)
    print(f"statuses={statuses}", flush=True)
    print(f"models={models}", flush=True)
    print("=" * 80, flush=True)


if __name__ == "__main__":
    asyncio.run(main())
