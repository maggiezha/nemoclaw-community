<!--
  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->

# Hermes

Self-improving agent with a learning loop, from
[Nous Research](https://github.com/NousResearch/hermes-agent); upstream source at
[`NVIDIA/NemoClaw/agents/hermes`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/hermes).
Like OpenClaw, Hermes is a long-running gateway agent with a dashboard — the difference is
its own OpenAI-compatible API port (`8642`) and health probe, and its own sandbox policy.

```bash
export HERMES_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-hermes-k8s:v0.0.104
./build-sandbox-image.sh
./create-sandbox.sh
./verify-sandbox.sh
./run-sandbox.sh   # keep in foreground
```

See [`../README.md`](../README.md) for the agent comparison table and shared policy
notes, and the recipe root [`README.md`](../../README.md) for cluster setup and
[Uninstall](../../README.md#uninstall) (substitute this agent's sandbox/provider names
below when tearing down).

| Env var | Default | Purpose |
|---------|---------|---------|
| `HERMES_SANDBOX_IMAGE` | — (required) | Pushed image reference |
| `HERMES_SANDBOX_NAME` | `hermes-onprem` | OpenShell sandbox name |
| `OPENSHELL_PROVIDER_NAME` | `onprem-hermes` | OpenShell inference provider name |
| `HERMES_SANDBOX_CPU` / `HERMES_SANDBOX_MEMORY` | `2` / `4Gi` | Sandbox pod requests |

Health/smoke checks used by `verify-sandbox.sh` (from
[`agents/hermes/manifest.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/agents/hermes/manifest.yaml)):
`hermes --version` and `GET http://localhost:8642/health`.

Not yet independently validated end-to-end against a live cluster — please file an issue
with anything you find while trying this on `dgx02`-class (8×H100) hardware.
