# Task

- Read the omo-slim.json understand how it is configured
- Read the json for available models, infer what details will be useful for deciding how to use the model
- Research on each model listed
- Generate an omo-slim.json that is optimal, only update the fields for the models

## omo-slim.jsonc

```jsonc
{
    "$schema": "https://raw.githubusercontent.com/alvinunreal/oh-my-opencode-slim/refs/heads/master/oh-my-opencode-slim.schema.json",
    "preset": "best",
    "presets": {
        "best": {
            "orchestrator": {
                "model": "openai/gpt-5.4",
            },
            "oracle": {
                "model": "openai/gpt-5.4",
                "variant": "high",
            },
            "librarian": {
                "model": "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo",
                "variant": "low",
            },
            "explorer": {
                "model": "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo",
                "variant": "low",
            },
            "designer": {
                "model": "github-copilot/gemini-3.1-pro-preview",
            },
            "fixer": {
                "model": "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo",
                "variant": "low",
            },
        },
    },
    "council": {
        "master": { "model": "openai/gpt-5.4" },
        "presets": {
            "default": {
                "alpha": { "model": "github-copilot/claude-opus-4.6" },
                "beta": { "model": "github-copilot/gemini-3.1-pro-preview" },
                "gamma": {
                    "model": "fireworks-ai/accounts/fireworks/routers/kimi-k2p5-turbo",
                },
            },
        },
    },
}
```

## Available Models

```json
{
    "aihubmix": {
        "models": {
            "coding-glm-4.7-free": {
                "context": 204800,
                "input": ["text"],
                "output": 131072,
                "variants": {}
            },
            "coding-glm-5-free": {
                "context": 204800,
                "input": ["text"],
                "output": 131072,
                "variants": {}
            },
            "coding-minimax-m2.1-free": {
                "context": 204800,
                "input": ["text"],
                "output": 131072,
                "variants": {}
            }
        }
    },
    "friendli": {
        "models": {
            "zai-org/GLM-4.7": {
                "context": 202752,
                "input": ["text"],
                "output": 202752,
                "variants": {}
            }
        }
    },
    "iflowcn": {
        "models": {
            "glm-4.6": {
                "context": 200000,
                "input": ["text"],
                "output": 128000,
                "variants": {}
            },
            "qwen3-235b-a22b-thinking-2507": {
                "context": 256000,
                "input": ["text"],
                "output": 64000,
                "variants": {
                    "high": { "reasoningEffort": "high" },
                    "low": { "reasoningEffort": "low" },
                    "medium": { "reasoningEffort": "medium" }
                }
            }
        }
    },
    "opencode": {
        "models": {
            "big-pickle": {
                "context": 200000,
                "input": ["text"],
                "output": 128000,
                "variants": {
                    "high": {
                        "thinking": { "budgetTokens": 16000, "type": "enabled" }
                    },
                    "max": {
                        "thinking": { "budgetTokens": 31999, "type": "enabled" }
                    }
                }
            },
            "gpt-5-nano": {
                "context": 400000,
                "input": ["text", "image"],
                "output": 128000,
                "variants": {
                    "high": {
                        "include": ["reasoning.encrypted_content"],
                        "reasoningEffort": "high",
                        "reasoningSummary": "auto"
                    },
                    "low": {
                        "include": ["reasoning.encrypted_content"],
                        "reasoningEffort": "low",
                        "reasoningSummary": "auto"
                    },
                    "medium": {
                        "include": ["reasoning.encrypted_content"],
                        "reasoningEffort": "medium",
                        "reasoningSummary": "auto"
                    },
                    "minimal": {
                        "include": ["reasoning.encrypted_content"],
                        "reasoningEffort": "minimal",
                        "reasoningSummary": "auto"
                    }
                }
            },
            "minimax-m2.5-free": {
                "context": 204800,
                "input": ["text"],
                "output": 131072,
                "variants": {}
            },
            "nemotron-3-super-free": {
                "context": 204800,
                "input": ["text"],
                "output": 128000,
                "variants": {
                    "high": { "reasoningEffort": "high" },
                    "low": { "reasoningEffort": "low" },
                    "medium": { "reasoningEffort": "medium" }
                }
            },
            "qwen3.6-plus-free": {
                "context": 1048576,
                "input": ["text"],
                "output": 64000,
                "variants": {
                    "high": { "reasoningEffort": "high" },
                    "low": { "reasoningEffort": "low" },
                    "medium": { "reasoningEffort": "medium" }
                }
            }
        }
    },
    "openrouter": {
        "models": {
            "nvidia/nemotron-3-nano-30b-a3b:free": {
                "context": 256000,
                "input": ["text"],
                "output": 256000,
                "variants": {}
            },
            "nvidia/nemotron-3-super-120b-a12b:free": {
                "context": 262144,
                "input": ["text"],
                "output": 262144,
                "variants": {}
            },
            "nvidia/nemotron-nano-12b-v2-vl:free": {
                "context": 128000,
                "input": ["text", "image"],
                "output": 128000,
                "variants": {}
            },
            "nvidia/nemotron-nano-9b-v2:free": {
                "context": 128000,
                "input": ["text"],
                "output": 128000,
                "variants": {}
            },
            "qwen/qwen3.6-plus-preview:free": {
                "context": 1000000,
                "input": ["text"],
                "output": 65536,
                "variants": {}
            },
            "qwen/qwen3.6-plus:free": {
                "context": 1000000,
                "input": ["text", "image", "video"],
                "output": 65536,
                "variants": {}
            },
            "stepfun/step-3.5-flash:free": {
                "context": 256000,
                "input": ["text"],
                "output": 256000,
                "variants": {}
            }
        }
    },
    "privatemode-ai": {
        "models": {
            "gpt-oss-120b": {
                "context": 128000,
                "input": ["text"],
                "output": 128000,
                "variants": {
                    "high": { "reasoningEffort": "high" },
                    "low": { "reasoningEffort": "low" },
                    "medium": { "reasoningEffort": "medium" }
                }
            }
        }
    },
    "zai": {
        "models": {
            "glm-4.5-flash": {
                "context": 131072,
                "input": ["text"],
                "output": 98304,
                "variants": {}
            },
            "glm-4.7-flash": {
                "context": 200000,
                "input": ["text"],
                "output": 131072,
                "variants": {}
            }
        }
    },
    "zenmux": {
        "models": {
            "stepfun/step-3.5-flash-free": {
                "context": 256000,
                "input": ["text"],
                "output": 64000,
                "variants": {
                    "high": { "reasoningEffort": "high" },
                    "low": { "reasoningEffort": "low" },
                    "medium": { "reasoningEffort": "medium" }
                }
            },
            "xiaomi/mimo-v2-flash-free": {
                "context": 262000,
                "input": ["text"],
                "output": 64000,
                "variants": {
                    "high": { "reasoningEffort": "high" },
                    "low": { "reasoningEffort": "low" },
                    "medium": { "reasoningEffort": "medium" }
                }
            },
            "z-ai/glm-4.6v-flash-free": {
                "context": 200000,
                "input": ["text", "image", "video"],
                "output": 64000,
                "variants": {}
            },
            "z-ai/glm-4.7-flash-free": {
                "context": 200000,
                "input": ["text"],
                "output": 64000,
                "variants": {}
            }
        }
    }
}
```
