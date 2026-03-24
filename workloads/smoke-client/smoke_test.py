import json
import os
import sys
import requests

BASE_URL = os.getenv("BASE_URL", "http://litellm:4000/v1")
MODELS = ["general-chat", "fast-chat", "tiny-chat"]
PROMPT = "Say hello in one short sentence and mention your model briefly."


def check(model: str) -> None:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": PROMPT}],
        "max_tokens": 64,
        "temperature": 0.1,
    }
    r = requests.post(
        f"{BASE_URL}/chat/completions",
        headers={"Authorization": "Bearer dummy-local-key", "Content-Type": "application/json"},
        data=json.dumps(payload),
        timeout=120,
    )
    r.raise_for_status()
    data = r.json()
    text = data["choices"][0]["message"]["content"]
    print(f"[{model}] {text}")


def main() -> None:
    for model in MODELS:
        check(model)


if __name__ == "__main__":
    main()
