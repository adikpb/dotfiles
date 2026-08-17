import json
import pprint
import re
import subprocess
import urllib.request
import pathlib
from typing import Any, TypedDict, cast


API_URL = "https://models.dev/api.json"


class APIDef(TypedDict):
    id: str
    url: str
    npm: str


class CacheCost(TypedDict):
    read: float
    write: float


class Cost(TypedDict):
    input: float
    output: float
    cache: CacheCost


class Limit(TypedDict):
    context: int
    output: int


class IOCapabilities(TypedDict):
    text: bool
    audio: bool
    image: bool
    video: bool
    pdf: bool


class Interleaved(TypedDict):
    field: str


class Capabilities(TypedDict):
    temperature: bool
    reasoning: bool
    attachment: bool
    toolcall: bool
    input: IOCapabilities
    output: IOCapabilities
    interleaved: Interleaved | bool


class Model(TypedDict):
    id: str
    providerID: str
    name: str
    api: APIDef
    status: str
    headers: dict[str, str]
    options: dict[str, str]
    cost: Cost
    limit: Limit
    capabilities: Capabilities
    release_date: str
    variants: dict[str, str]


class RawAPIModel(TypedDict):
    id: str
    name: str
    family: str | None
    attachment: bool
    reasoning: bool
    tool_call: bool
    temperature: bool
    knowledge: str | None
    release_date: str
    last_updated: str
    modalities: dict[str, list[str]]
    open_weights: bool
    cost: dict[str, float]
    limit: dict[str, int]
    status: str | None


class RawAPIProvider(TypedDict):
    id: str
    name: str
    npm: str
    api: str
    doc: str
    models: dict[str, RawAPIModel]


Models = dict[str, dict[str, Model]]


CURR_DIR = pathlib.Path(".").resolve()
MINIMUM_CONTEXT_WINDOW_SIZE = 128_000
MINIMUM_OUTPUT_LENGTH = 32_000
PROVIDER_ID_BLACKLIST = {
    "aihubmix",
    "alibaba-coding-plan",
    "alibaba-coding-plan-cn",
    "github-copilot",
    "github-models",
    "gitlab",
    "huggingface",
    "iflowcn",
    "jiekou",
    "kilo",
    "kimi-for-coding",
    "kuae-cloud-coding-plan",
    "llmgateway",
    "lmstudio",
    "minimax-cn-coding-plan",
    "minimax-coding-plan",
    "modelscope",
    "nova",
    "nvidia",
    "poe",
    "privatemode-ai",
    "qiniu-ai",
    "siliconflow-cn",
    "tencent-coding-plan",
    "tencent-tokenhub",
    "the-grid-ai",
    "wafer.ai",
    "xiaomi-token-plan-ams",
    "xiaomi-token-plan-cn",
    "xiaomi-token-plan-sgp",
    "zai-coding-plan",
    "zenmux",
    "zhipuai",
    "zhipuai-coding-plan",
}
MODEL_BLACKLIST = {"nemotron"}


def validate_model(key: str, data: dict[str, Any]) -> Model:
    errors: list[str] = []

    def check(path: str, value: Any, expected_type: type | tuple[type, ...]) -> None:
        if not isinstance(value, expected_type):
            type_name = (
                " | ".join(t.__name__ for t in expected_type)
                if isinstance(expected_type, tuple)
                else expected_type.__name__
            )
            errors.append(f"{path}: expected {type_name}, got {type(value).__name__}")

    check("id", data.get("id"), str)
    check("providerID", data.get("providerID"), str)
    check("name", data.get("name"), str)
    check("status", data.get("status"), str)

    limit: dict[str, Any] = data.get("limit") or {}
    check("limit.context", limit.get("context"), int)
    check("limit.output", limit.get("output"), int)

    cost: dict[str, Any] = data.get("cost") or {}
    check("cost.input", cost.get("input"), (int, float))
    check("cost.output", cost.get("output"), (int, float))

    caps: dict[str, Any] = data.get("capabilities") or {}
    check("capabilities.reasoning", caps.get("reasoning"), bool)
    check("capabilities.toolcall", caps.get("toolcall"), bool)
    check("capabilities.input.text", (caps.get("input") or {}).get("text"), bool)
    check("capabilities.output.text", (caps.get("output") or {}).get("text"), bool)

    interleaved: Any = caps.get("interleaved")
    if not isinstance(interleaved, (bool, dict)):
        errors.append(
            f"capabilities.interleaved: expected bool or dict, got {type(interleaved).__name__}"
        )

    if errors:
        raise ValueError(
            f"Invalid model {key}:\n" + "\n".join(f"  - {e}" for e in errors)
        )

    return cast(Model, data)


def include(model: Model) -> bool:
    caps = model.get("capabilities") or {}
    limit = model.get("limit") or {}
    cost = model.get("cost") or {}
    blacklisted = not any(True for m in MODEL_BLACKLIST if m in model.get("name").lower())
    return (
        blacklisted
        and cost.get("input", 1) == 0
        and cost.get("output", 1) == 0
        and bool(caps.get("reasoning", False))
        and bool(caps.get("toolcall", False))
        and int(limit.get("context", 0)) >= MINIMUM_CONTEXT_WINDOW_SIZE
        and int(limit.get("output", 0)) >= MINIMUM_OUTPUT_LENGTH
        and bool((caps.get("input") or {}).get("text", False))
        and bool((caps.get("output") or {}).get("text", False))
        and model.get("status") != "deprecated"
        and model.get("status") != "alpha"
    )


def clean_model(model: Model) -> dict[str, Any]:
    limit = model.get("limit") or {}
    caps = model.get("capabilities") or {}
    inp: dict[str, Any] = caps.get("input") or {}

    ret = {
        "context": limit.get("context"),
        "input": [modality for modality, supported in inp.items() if supported],
        "variants": [i for i in (model.get("variants") or {})],
    }

    if ret.get("variants") == []:
        ret.pop("variants")

    return ret


def parse_cli_output(text: str) -> Models:
    result: Models = {}
    regex = re.compile(r"^(\S+)\n(\{[\s\S]*?\n\})", re.MULTILINE)

    for match in regex.finditer(text):
        full_key, json_str = match.group(1), match.group(2)
        provider, _, model_key = full_key.partition("/")
        try:
            model = validate_model(full_key, json.loads(json_str))
        except (json.JSONDecodeError, ValueError) as e:
            print(f"Skipping {full_key}: {e}")
            continue
        result.setdefault(provider, {})[model_key] = model

    return result


def _modalities_from(modality_list: list[str]) -> dict[str, bool]:
    return {
        "text": "text" in modality_list,
        "audio": "audio" in modality_list,
        "image": "image" in modality_list,
        "video": "video" in modality_list,
        "pdf": "pdf" in modality_list,
    }


def convert_raw_to_model(provider_id: str, model_id: str, raw: RawAPIModel) -> Model:
    modalities = raw.get("modalities") or {}
    caps: dict[str, Any] = {
        "temperature": raw.get("temperature", True),
        "reasoning": raw.get("reasoning", False),
        "attachment": raw.get("attachment", False),
        "toolcall": raw.get("tool_call", True),
        "input": _modalities_from(modalities.get("input", [])),
        "output": _modalities_from(modalities.get("output", [])),
        "interleaved": False,
    }

    cost = raw.get("cost") or {}
    limit = raw.get("limit") or {}

    return {
        "id": raw.get("id", model_id),
        "providerID": provider_id,
        "name": raw.get("name", model_id),
        "api": {"id": "", "url": "", "npm": ""},
        "status": raw.get("status") or "active",
        "headers": {},
        "options": {},
        "cost": {
            "input": cost.get("input", 0),
            "output": cost.get("output", 0),
            "cache": {"read": 0, "write": 0},
        },
        "limit": {
            "context": limit.get("context", 0),
            "output": limit.get("output", 0),
        },
        "capabilities": caps,
        "release_date": raw.get("release_date", ""),
        "variants": {},
    }


def fetch_api_models() -> Models:
    """Fetch models from the API URL for additional providers."""
    request = urllib.request.Request(API_URL)
    request.add_header("User-Agent", "Mozilla/5.0 (compatible; free-models/1.0)")
    with urllib.request.urlopen(request) as response:
        raw_data: dict[str, RawAPIProvider] = json.load(response)

    result: Models = {}
    for provider_id, provider in raw_data.items():
        provider_models: dict[str, Model] = {}
        for model_id, raw_model in provider.get("models", {}).items():
            full_key = f"{provider_id}/{model_id}"
            try:
                provider_models[model_id] = convert_raw_to_model(
                    provider_id, model_id, raw_model
                )
            except Exception as e:
                print(f"Skipping {full_key}: {e}")
                continue
        if provider_models:
            result[provider_id] = provider_models

    return result


def fetch_models() -> Models:
    # CLI has variants and API info; API has more providers
    result = subprocess.run(
        ["opencode", "models", "--refresh", "--verbose"],
        capture_output=True,
        text=True,
        check=True,
    )
    cli_models = parse_cli_output(result.stdout)
    api_models = fetch_api_models()

    # Merge: CLI primary, API fills gaps
    for pid, models in api_models.items():
        if pid not in cli_models:
            cli_models[pid] = models
        else:
            cli_models[pid] |= {
                mid: m for mid, m in models.items() if mid not in cli_models[pid]
            }
    return cli_models


def main() -> None:
    data = fetch_models()

    with open(CURR_DIR / "models.json", "w") as f:
        json.dump(data, f, sort_keys=True, separators=(",", ":"))

    # non-inverted: provider -> model
    filtered: dict[str, dict[str, dict[str, Any]]] = {}
    for provider_id, models in data.items():
        if provider_id in PROVIDER_ID_BLACKLIST:
            continue
        filtered_models: dict[str, dict[str, Any]] = {
            model_id: clean_model(model)
            for model_id, model in models.items()
            if include(model)
        }
        if not filtered_models:
            continue
        filtered[provider_id] = {"models": filtered_models}

    # Providers with free models in API but not in CLI
    cli_providers: set[str] = set()
    result = subprocess.run(
        ["opencode", "models"],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in result.stdout.strip().split("\n"):
        if "/" in line:
            cli_providers.add(line.split("/")[0])

    api_only_providers = sorted(set(filtered.keys()) - cli_providers)

    # Only include models from CLI providers in JSON files
    cli_only_filtered = {pid: filtered[pid] for pid in filtered if pid in cli_providers}

    # inverted: model -> provider (only CLI providers)
    inverted: dict[str, dict[str, dict[str, Any]]] = {}
    for provider_id, provider in cli_only_filtered.items():
        for model_id, model in provider["models"].items():
            org, _, model_name = model_id.rpartition("/")
            provider_key = f"{provider_id}/{org}" if org else provider_id
            inverted.setdefault(model_name, {})[provider_key] = model

    with open(CURR_DIR / "free-models.json", "w") as f:
        json.dump(cli_only_filtered, f, sort_keys=True, indent=2)

    with open(CURR_DIR / "free-models-by-model.json", "w") as f:
        json.dump(inverted, f, sort_keys=True, indent=2)

    pprint.pprint(sorted({m.upper() for m in inverted}), compact=True, width=120)

    if api_only_providers:
        print("\n--- Free providers in API but not in CLI ---")
        print("NOTE: You need login to these providers to see their model variants.")
        for p in api_only_providers:
            models = sorted(filtered[p]["models"].keys())
            print(f"  {p}")
            for m in models:
                print(f"    - {m}")


if __name__ == "__main__":
    main()
