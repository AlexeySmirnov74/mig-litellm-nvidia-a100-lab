import json
import os
import time
from typing import Any

import httpx
from fastapi import FastAPI, Request, Response as FastAPIResponse
from fastapi.responses import JSONResponse, StreamingResponse, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

LITELLM_BASE_URL = os.getenv("LITELLM_BASE_URL", "http://litellm:4000")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY", "dummy-local-key")

app = FastAPI(title="context-guard")

REQUESTS_TOTAL = Counter(
    "llm_guard_requests_total",
    "Total requests handled by context-guard",
    ["model", "status"],
)

REQUEST_DURATION = Histogram(
    "llm_guard_request_duration_seconds",
    "End-to-end request latency seen by context-guard",
    ["model", "status"],
    buckets=(0.05, 0.1, 0.2, 0.35, 0.5, 0.75, 1, 1.5, 2, 3, 5, 8, 13, 21, 34),
)

CONTEXT_RESETS = Counter(
    "llm_guard_context_resets_total",
    "How many times context-guard reset history because of context overflow",
    ["model", "reason"],
)

FALLBACK_FAILURES = Counter(
    "llm_guard_fallback_failures_total",
    "How many fallback retries still failed",
    ["model", "reason"],
)

INFLIGHT = Gauge(
    "llm_guard_inflight_requests",
    "Current in-flight requests inside context-guard",
    ["model"],
)


MODEL_POLICY = {
    "general-chat": {
        "input_char_limit": 2200,
        "max_tokens": 256,
        "system_prompt": (
            "You are the primary chat model tier. "
            "Previous chat history was removed due to context limits. "
            "Answer the latest user request clearly and continue naturally."
        ),
    },
    "fast-chat": {
        "input_char_limit": 1200,
        "max_tokens": 128,
        "system_prompt": (
            "You are the fast chat model tier. "
            "Previous chat history was removed due to context limits. "
            "Answer only the latest user request clearly and concisely."
        ),
    },
    "tiny-chat": {
        "input_char_limit": 450,
        "max_tokens": 32,
        "system_prompt": (
            "You are the tiny-context model tier. "
            "Previous chat history was removed due to context limits. "
            "Answer only the latest user request briefly and clearly."
        ),
    },
}


def _auth_headers(incoming_headers: dict[str, str]) -> dict[str, str]:
    headers = {
        "Authorization": f"Bearer {LITELLM_API_KEY}",
        "Content-Type": "application/json",
    }
    if "accept" in incoming_headers:
        headers["Accept"] = incoming_headers["accept"]
    return headers


def _is_context_error(status_code: int, body_text: str) -> bool:
    if status_code not in (400, 401, 404, 422, 500):
        return False
    text = body_text.lower()
    patterns = [
        "contextwindowexceedederror",
        "inputs must have less than",
        "inputs tokens + `max_new_tokens` must be <=",
        "inputs tokens + max_new_tokens must be <=",
        "input validation error",
        "must have less than 384 tokens",
        "must be <= 512",
        "must be <= 1024",
        "must be <= 2048",
    ]
    return any(p in text for p in patterns)


def _get_policy(model: str) -> dict[str, Any]:
    return MODEL_POLICY.get(
        model,
        {
            "input_char_limit": 1000,
            "max_tokens": 128,
            "system_prompt": (
                "Previous chat history was removed due to context limits. "
                "Answer only the latest user request."
            ),
        },
    )


def _extract_last_user_content(messages: list[dict[str, Any]], char_limit: int) -> str:
    user_messages = [m for m in messages if m.get("role") == "user"]
    if not user_messages:
        return "Repeat your last answer briefly."

    content = user_messages[-1].get("content", "")
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))
        content = "\n".join(parts)

    if not isinstance(content, str):
        content = str(content)

    content = content.strip()
    return content[:char_limit]


def _build_fallback_payload(payload: dict[str, Any]) -> dict[str, Any]:
    model = payload.get("model", "unknown")
    policy = _get_policy(model)

    messages = payload.get("messages", [])
    last_user_content = _extract_last_user_content(
        messages,
        char_limit=policy["input_char_limit"],
    )

    short_system = {
        "role": "system",
        "content": policy["system_prompt"],
    }

    last_user = {
        "role": "user",
        "content": last_user_content,
    }

    new_payload = dict(payload)
    new_payload["messages"] = [short_system, last_user]
    new_payload["max_tokens"] = policy["max_tokens"]
    new_payload["stream"] = False
    return new_payload


def _prepend_notice_to_json_response(data: dict[str, Any], model: str) -> dict[str, Any]:
    notice = f"⚠ История чата была очищена из-за ограничения контекста модели {model}.\n\n"
    try:
        choices = data.get("choices", [])
        if choices and "message" in choices[0] and "content" in choices[0]["message"]:
            content = choices[0]["message"]["content"] or ""
            choices[0]["message"]["content"] = notice + content
    except Exception:
        pass
    return data


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/metrics")
async def metrics() -> FastAPIResponse:
    return FastAPIResponse(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/v1/models")
async def models(request: Request):
    headers = _auth_headers(dict(request.headers))
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.get(f"{LITELLM_BASE_URL}/v1/models", headers=headers)
        return Response(
            content=resp.content,
            status_code=resp.status_code,
            media_type=resp.headers.get("content-type", "application/json"),
        )


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    payload = await request.json()
    model = payload.get("model", "unknown")
    target_url = f"{LITELLM_BASE_URL}/v1/chat/completions"
    headers = _auth_headers(dict(request.headers))
    started = time.perf_counter()

    INFLIGHT.labels(model=model).inc()
    try:
        async with httpx.AsyncClient(timeout=300.0) as client:
            first = await client.post(target_url, headers=headers, json=payload)

            if first.is_success:
                REQUESTS_TOTAL.labels(model=model, status="ok").inc()
                REQUEST_DURATION.labels(model=model, status="ok").observe(
                    time.perf_counter() - started
                )
                return Response(
                    content=first.content,
                    status_code=first.status_code,
                    media_type=first.headers.get("content-type", "application/json"),
                )

            body_text = first.text
            if not _is_context_error(first.status_code, body_text):
                REQUESTS_TOTAL.labels(model=model, status=f"http_{first.status_code}").inc()
                REQUEST_DURATION.labels(model=model, status=f"http_{first.status_code}").observe(
                    time.perf_counter() - started
                )
                return Response(
                    content=first.content,
                    status_code=first.status_code,
                    media_type=first.headers.get("content-type", "application/json"),
                )

            CONTEXT_RESETS.labels(model=model, reason="context_overflow").inc()
            fallback_payload = _build_fallback_payload(payload)
            second = await client.post(target_url, headers=headers, json=fallback_payload)

            if not second.is_success:
                FALLBACK_FAILURES.labels(model=model, reason="retry_failed").inc()
                REQUESTS_TOTAL.labels(model=model, status=f"http_{second.status_code}").inc()
                REQUEST_DURATION.labels(model=model, status=f"http_{second.status_code}").observe(
                    time.perf_counter() - started
                )
                return Response(
                    content=second.content,
                    status_code=second.status_code,
                    media_type=second.headers.get("content-type", "application/json"),
                )

            data = second.json()
            data = _prepend_notice_to_json_response(data, model=model)
            REQUESTS_TOTAL.labels(model=model, status="ok_reset").inc()
            REQUEST_DURATION.labels(model=model, status="ok_reset").observe(
                time.perf_counter() - started
            )

            if bool(payload.get("stream", False)):
                async def gen():
                    yield f"data: {json.dumps(data, ensure_ascii=False)}\n\n"
                    yield "data: [DONE]\n\n"
                return StreamingResponse(gen(), media_type="text/event-stream")

            return JSONResponse(status_code=200, content=data)

    finally:
        INFLIGHT.labels(model=model).dec()



