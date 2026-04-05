import json
import pprint
import re
import subprocess
import pathlib
from typing import Any, TypedDict, cast


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


Models = dict[str, dict[str, Model]]


CURR_DIR = pathlib.Path(".").resolve()
MINIMUM_CONTEXT_WINDOW_SIZE = 128_000
MINIMUM_OUTPUT_LENGTH = 64_000
PROVIDER_ID_BLACKLIST = {
    "aihubmix",
    "alibaba-coding-plan",
    "alibaba-coding-plan-cn",
    "github-copilot",
    "gitlab",
    "kilo",
    "lmstudio",
    "minimax-cn-coding-plan",
    "minimax-coding-plan",
    "nova",
    "nvidia",
    "ollama-cloud",
    "qiniu-ai",
    "zai-coding-plan",
    "zhipuai-coding-plan",
}


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
    return (
        cost.get("input", 1) == 0
        and cost.get("output", 1) == 0
        and bool(caps.get("reasoning", False))
        and bool(caps.get("toolcall", False))
        and int(limit.get("context", 0)) >= MINIMUM_CONTEXT_WINDOW_SIZE
        and int(limit.get("output", 0)) >= MINIMUM_OUTPUT_LENGTH
        and bool((caps.get("input") or {}).get("text", False))
        and bool((caps.get("output") or {}).get("text", False))
        and model.get("status") != "deprecated"
    )


def clean_model(model: Model) -> dict[str, Any]:
    limit = model.get("limit") or {}
    caps = model.get("capabilities") or {}
    inp: dict[str, Any] = caps.get("input") or {}

    return {
        "context": limit.get("context"),
        "output": limit.get("output"),
        "input": [modality for modality, supported in inp.items() if supported],
        "variants": model.get("variants") or {},
    }


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


def fetch_models() -> Models:
    result = subprocess.run(
        ["opencode", "models", "--refresh", "--verbose"],
        capture_output=True,
        text=True,
        check=True,
    )
    return parse_cli_output(result.stdout)


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

    # inverted: model -> provider
    inverted: dict[str, dict[str, dict[str, Any]]] = {}
    for provider_id, provider in filtered.items():
        for model_id, model in provider["models"].items():
            org, _, model_name = model_id.rpartition("/")
            provider_key = f"{provider_id}/{org}" if org else provider_id
            inverted.setdefault(model_name, {})[provider_key] = model

    with open(CURR_DIR / "free-models.json", "w") as f:
        json.dump(filtered, f, sort_keys=True, separators=(",", ":"))

    with open(CURR_DIR / "free-models-by-model.json", "w") as f:
        json.dump(inverted, f, sort_keys=True, separators=(",", ":"))

    unique_models: set[str] = {model.upper() for model in inverted}
    pprint.pprint(sorted(unique_models), compact=True, width=120)


if __name__ == "__main__":
    main()
