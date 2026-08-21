<!--
  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0
-->

# Deep Agents Code

Terminal coding agent built on the
[Deep Agents SDK](https://docs.langchain.com/oss/python/deepagents/code/overview);
upstream source at
[`NVIDIA/NemoClaw/agents/langchain-deepagents-code`](https://github.com/NVIDIA/NemoClaw/tree/main/agents/langchain-deepagents-code).

**This agent has no long-running gateway or dashboard** (`runtime.kind: terminal` in its
manifest) — it is invoked headlessly, one prompt at a time, via `dcode -n "<prompt>"`.
There is intentionally no `run-sandbox.sh` here; use `run-prompt.sh` instead.

```bash
export DEEPAGENTS_SANDBOX_IMAGE=registry.example.com/team/nemoclaw-deepagents-k8s:v0.0.104
./build-sandbox-image.sh
./create-sandbox.sh
./verify-sandbox.sh
./run-prompt.sh "Explain this repository in one sentence."
```

For an interactive session instead of one-shot prompts, use a terminal that supports a
TTY directly with OpenShell:

```bash
openshell sandbox exec -n "${DEEPAGENTS_SANDBOX_NAME:-deepagents-onprem}" -- dcode
```

See [`../README.md`](../README.md) for the agent comparison table and shared policy
notes, and the recipe root [`README.md`](../../README.md) for cluster setup and
[Uninstall](../../README.md#uninstall) (substitute this agent's sandbox/provider names
below when tearing down).

| Env var | Default | Purpose |
|---------|---------|---------|
| `DEEPAGENTS_SANDBOX_IMAGE` | — (required) | Pushed image reference |
| `DEEPAGENTS_SANDBOX_NAME` | `deepagents-onprem` | OpenShell sandbox name |
| `OPENSHELL_PROVIDER_NAME` | `onprem-deepagents` | OpenShell inference provider name |
| `DEEPAGENTS_SANDBOX_CPU` / `DEEPAGENTS_SANDBOX_MEMORY` | `2` / `4Gi` | Sandbox pod requests |

Smoke checks used by `verify-sandbox.sh` (from this agent's own
[`manifest.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/agents/langchain-deepagents-code/manifest.yaml)
`runtime.smoke_commands`): `dcode --version`, a `config.toml` existence check, then a real
`dcode -n "<prompt>"` call through `https://inference.local`.

Not yet independently validated end-to-end against a live cluster — please file an issue
with anything you find while trying this on `dgx02`-class (8×H100) hardware.
