<!--
  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->

# OpenClaw

Default agent for this recipe. Gateway-based agent with a plugin ecosystem
([openclaw.ai](https://openclaw.ai)); upstream source at
[`NVIDIA/NemoClaw/agents/openclaw`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/openclaw)
(image still builds from the repo root `Dockerfile` — see that manifest's `_legacy_paths`).

```bash
export NEMOCLAW_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-openclaw-k8s:v0.0.104
./build-sandbox-image.sh
./create-sandbox.sh
./verify-sandbox.sh
./run-sandbox.sh   # keep in foreground
```

See [`../README.md`](../README.md) for the agent comparison table and shared policy
notes, and the recipe root [`README.md`](../../README.md) for cluster setup,
[OpenShell details](../../README.md#openshell-details), and
[Uninstall](../../README.md#uninstall).

| Env var | Default | Purpose |
|---------|---------|---------|
| `NEMOCLAW_SANDBOX_IMAGE` | — (required) | Pushed image reference |
| `NEMOCLAW_SANDBOX_NAME` | `nemoclaw-onprem` | OpenShell sandbox name |
| `OPENSHELL_PROVIDER_NAME` | `onprem-ollama` | OpenShell inference provider name |
| `NEMOCLAW_SANDBOX_CPU` / `NEMOCLAW_SANDBOX_MEMORY` | `2` / `4Gi` | Sandbox pod requests |

Health/smoke check used by `verify-sandbox.sh`: `openclaw plugins inspect nemoclaw --json`.
