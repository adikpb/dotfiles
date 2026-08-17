# Task

- Read and understand:
    - omo-slim.json
    - available model json
- research on each model listed
- generate an omo-slim.json that is optimal, only update the fields for the models

## Agent description

- **Orchestrator**: An AI coding orchestrator that delegates tasks to specialized agents (explorer, librarian, oracle, fixer) to optimize for quality, speed, cost, and reliability.
- **Oracle**: A read-only strategic advisor for architecture decisions, complex debugging, code review, and simplification guidance.
- **Librarian**: A research specialist that finds official docs, library examples, and codebase patterns from external sources.
- **Explorer**: A read-only codebase search specialist that quickly locates files, symbols, and patterns via grep, glob, and AST queries.
- **Fixer**: A fast, execution-only specialist that implements well-defined code changes without research or planning.

## omo-slim.json

```json
{
    "preset": "openai",
    "presets": {
        "openai": {
            "orchestrator": {
                "model": "openai/gpt-5.5-fast"
            },
            "oracle": {
                "model": "openai/gpt-5.5-fast",
                "variant": "high"
            },
            "librarian": {
                "model": "openai/gpt-5.3-codex-spark",
                "variant": "low"
            },
            "explorer": {
                "model": "openai/gpt-5.3-codex-spark",
                "variant": "low"
            },
            },
            "fixer": {
                "model": "openai/gpt-5.3-codex-spark",
                "variant": "low"
            }
        }
    },
}
```

## Available models

```json
{
  "opencode": {
    "models": {
      "big-pickle": {
        "context": 200000,
        "input": [
          "text"
        ]
      },
      "deepseek-v4-flash-free": {
        "context": 200000,
        "input": [
          "text"
        ],
        "variants": [
          "low",
          "medium",
          "high",
          "max"
        ]
      },
      "mimo-v2.5-free": {
        "context": 200000,
        "input": [
          "text",
          "audio",
          "image",
          "video"
        ],
        "variants": [
          "low",
          "medium",
          "high"
        ]
      },
      "minimax-m3-free": {
        "context": 200000,
        "input": [
          "text",
          "image",
          "video"
        ]
      }
    }
  },
  "openrouter": {
    "models": {
      "google/gemma-4-26b-a4b-it:free": {
        "context": 262144,
        "input": [
          "text",
          "image",
          "video"
        ]
      },
      "google/gemma-4-31b-it:free": {
        "context": 262144,
        "input": [
          "text",
          "image",
          "video"
        ]
      },
      "moonshotai/kimi-k2.6:free": {
        "context": 262144,
        "input": [
          "text",
          "image"
        ]
      },
      "openai/gpt-oss-120b:free": {
        "context": 131072,
        "input": [
          "text"
        ],
        "variants": [
          "none",
          "minimal",
          "low",
          "medium",
          "high",
          "xhigh"
        ]
      },
      "poolside/laguna-m.1:free": {
        "context": 262144,
        "input": [
          "text"
        ]
      },
      "poolside/laguna-xs.2:free": {
        "context": 262144,
        "input": [
          "text"
        ]
      },
      "z-ai/glm-4.5-air:free": {
        "context": 131072,
        "input": [
          "text"
        ]
      }
    }
  }
}
```
