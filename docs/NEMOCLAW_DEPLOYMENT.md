# Deploying Brewlytics with NemoClaw

This guide walks through running the 4-agent Brewlytics stack inside a [NemoClaw](https://github.com/NVIDIA/NemoClaw) sandbox — NVIDIA's reference stack that drops OpenClaw into an OpenShell-managed Landlock + seccomp + netns jail with declarative egress control.

> **Status:** NemoClaw is alpha (released 2026-03-16). The blueprint, policy, Dockerfile, and entrypoint in `nemoclaw/` are templates — validate against the current NemoClaw schema before relying on them. See [Known limitations](#known-limitations) at the end.

## Why bother

Vanilla Docker gives you process isolation. NemoClaw adds:

| Control | Vanilla Docker | NemoClaw sandbox |
|---|---|---|
| Filesystem | Full access within container FS | Landlock: `/sandbox` read-only except `/sandbox/.openclaw-data` |
| Network egress | All outbound traffic | Declarative allowlist (only the hosts in `policy.yaml`) |
| User privilege | root (or configured user) | Unprivileged `sandbox` user with seccomp restrictions |
| Image supply chain | `:latest` drift possible | Pinned by sha256 digest, verified at onboard |
| Credential storage | Container env vars | OpenShell credential store + baked into private image |

If a model is ever jailbroken into running shell commands under NemoClaw, those commands hit Landlock before touching your filesystem, and netns before touching the network.

## What's in this repo for NemoClaw

```
nemoclaw/
├── blueprint.yaml           # NemoClaw blueprint (sandbox image + inference profiles)
├── policy-additions.yaml    # extra network_policies (openrouter, vllm, nim, python-telegram)
├── Dockerfile.sandbox       # derivative sandbox image (FROM NVIDIA upstream, bakes our config)
└── entrypoint-sandbox.sh    # first-boot config + DB + workspaces under /sandbox/.openclaw-data
```

## How the pieces fit

```
Host                                        Sandbox (netns + Landlock)
──────────────────────────────              ────────────────────────────────
NemoClaw CLI                                /app/                       (read-only image layer)
  │                                         ├── openclaw-config/
  │ onboard + build                         ├── generate_starbucks_db.py
  ▼                                         └── entrypoint-sandbox.sh
OpenShell runtime                           /sandbox/.openclaw/         (Landlock read-only)
  │                                         ├── openclaw.json           → symlink to .openclaw-data/
  │ spawns                                  └── exec-approvals.json     → symlink to .openclaw-data/
  ▼
brewlytics-sandbox container                /sandbox/.openclaw-data/    (writable)
                                            ├── openclaw.json           (generated at first boot)
                                            ├── exec-approvals.json     (generated at first boot)
                                            ├── shared-data/
                                            │   └── starbucks_business.db
                                            └── workspaces/
                                                ├── main/                 (concierge)
                                                ├── analyst/
                                                ├── data-scientist/
                                                └── customer-intel/
```

Credentials never live in the image: `openclaw.json` in `/sandbox/.openclaw/` is a symlink (baked by `Dockerfile.sandbox`) that resolves to the writable `.openclaw-data/openclaw.json`. The entrypoint generates that file at first boot from env vars the NemoClaw onboard wizard injects.

## Prerequisites

- Linux host (macOS with Docker Desktop works but is tested-with-limitations per NemoClaw's docs)
- Docker running and reachable from the host user
- NemoClaw installed (`curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash`)
- 8+ GB RAM, 20+ GB free disk (sandbox image is ~2.4 GB compressed)
- One of:
  - OpenRouter API key (`OPENROUTER_API_KEY`) — matches the vanilla-Docker deployment
  - NVIDIA API key (`NVIDIA_API_KEY`) — uses NemoClaw's default Nemotron inference
  - A reachable NIM or vLLM endpoint with `NIM_API_KEY` / `VLLM_API_KEY`
- Telegram bot token + numeric user ID

## Deployment

### 1. Build the derivative sandbox image

```bash
git clone https://github.com/cubist38/openclaw-analyst.git
cd openclaw-analyst

docker build \
  -f nemoclaw/Dockerfile.sandbox \
  -t brewlytics-sandbox:$(git rev-parse --short HEAD) \
  .

# Record the digest — you'll paste it into blueprint.yaml next.
docker images --digests brewlytics-sandbox | head
```

The build pins the upstream OpenClaw sandbox by digest (see `UPSTREAM_DIGEST` arg) and layers your config + Python deps on top. No credentials are baked in.

### 2. Pin the image in the blueprint

Edit `nemoclaw/blueprint.yaml`:

- Top-level `digest:` — the sha256 of the image you just built
- `components.sandbox.image` — `brewlytics-sandbox@sha256:<same digest>`

### 3. Pick an inference profile

`blueprint.yaml` ships four profiles:

| Profile | Endpoint | Credential env | When to use |
|---|---|---|---|
| `default` | `https://integrate.api.nvidia.com/v1` | `NVIDIA_API_KEY` | NemoClaw's happy path — NVIDIA-hosted Nemotron |
| `openrouter` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` | Match the vanilla-Docker deployment (Grok, Claude, GPT, etc.) |
| `nim-local` | `http://nim-service.local:8000/v1` | `NIM_API_KEY` | On-prem NIM microservice |
| `vllm` | `http://vllm.local:8000/v1` | `VLLM_API_KEY` | Self-hosted vLLM |

Each profile has a matching block in `nemoclaw/policy-additions.yaml` that opens the egress path. Enable only the one you need — delete the others to keep the allowlist tight.

For `nim-local` and `vllm`, replace `nim-service.local` / `vllm.local` in both files with an FQDN your sandbox can actually resolve (LAN DNS entry, `/etc/hosts` injection via OpenShell, or a private hostname).

### 4. Run `nemoclaw onboard`

```bash
export TELEGRAM_BOT_TOKEN=<your-bot-token>
export TELEGRAM_ALLOW_FROM=<your-numeric-user-id>

# Pick ONE inference credential:
export OPENROUTER_API_KEY=<sk-or-…>        # if using the `openrouter` profile
# export NVIDIA_API_KEY=<nvapi-…>           # if using the `default` or `nim-local` profile
# export VLLM_API_KEY=vllm-local            # if using the `vllm` profile; any value works without auth
# export OPENCLAW_MODEL=vllm/<your-model-id>
# export VLLM_BASE_URL=http://vllm.local:8000/v1

nemoclaw onboard \
  --blueprint ./nemoclaw/blueprint.yaml \
  --profile openrouter
```

The wizard:

- Reads your env vars (or prompts if missing)
- Builds the OpenShell sandbox from the pinned image
- Applies the base openclaw-sandbox policy + your `policy-additions.yaml`
- Stores the Telegram token hash in the sandbox registry for rotation detection
- Starts the gateway on port 18789 (forwarded to your host)

> **Note:** NemoClaw's wizard may not yet support `--blueprint` pointing at a file outside its tree — if it errors, symlink your blueprint into NemoClaw's expected location (check `nemoclaw onboard --help` on your version).

### 5. Verify

```bash
# Agents registered?
nemoclaw my-assistant connect
openclaw agents list
# Expect: main, analyst, data-scientist, customer-intel

# Allowlists look right?
cat /sandbox/.openclaw-data/exec-approvals.json | python3 -m json.tool
# Expect: main has only invoke-specialist.sh; specialists have sqlite3 + python3

# Network policy enforced?
curl https://api.github.com 2>&1 | head -3
# Expect: a netns / Landlock error — github.com is NOT allowlisted

curl https://api.telegram.org/bot123/getMe 2>&1 | head -3
# Expect: API response (or 404 for bad token) — telegram IS allowlisted

# End-to-end
# (from your Telegram client) message the bot: "top 5 stores by revenue"
# → concierge routes to analyst → analyst queries DB, generates chart → chart appears in Telegram
```

## Known limitations

1. **Custom-blueprint UX is alpha.** NemoClaw ships its own blueprint and the exact CLI for loading an external one varies by version. If `--blueprint ./nemoclaw/blueprint.yaml` fails, fall back to editing NemoClaw's in-tree blueprint directly and pointing `components.sandbox.image` at your built image.

2. **`openclaw.json` is immutable via Landlock.** We work around this with a symlink-to-writable pattern (see [How the pieces fit](#how-the-pieces-fit)), which works for reads but means the OpenClaw Control UI cannot edit the config file in-place. Rotating Telegram tokens = recreate the sandbox (`nemoclaw onboard` again).

3. **Chart delivery needs python3 in the telegram policy.** Upstream NemoClaw allows only `node` to reach `api.telegram.org`. Our `policy-additions.yaml` adds `python3` (for `brew_chart.send()` and `send_photo.py`). If a future NemoClaw release tightens the base policy, you may need to update this.

4. **Agent-to-agent delegation uses `invoke-specialist.sh`.** Inside the sandbox, the concierge's allowlist contains only that wrapper — the wrapper hard-codes the three specialist names and forbids any other `openclaw` subcommand. A compromised concierge can't escalate via `openclaw approvals allowlist add`.

5. **Specialists invoke `openclaw agent --agent X --local` through the wrapper.** Each specialist call is an in-process OpenClaw turn (not a new container). If you later want each specialist in its own sandbox (deeper defense-in-depth), that's a bigger refactor — NemoClaw currently assumes one sandbox per assistant.

6. **DB generation runs inside the sandbox.** `generate_starbucks_db.py` needs `HOME` to be writable, and Landlock restricts `/sandbox`. The entrypoint uses a `mktemp -d` staging path to side-step this. If you change the generator to hardcode a path, update `entrypoint-sandbox.sh` accordingly.

## Updating

- **Bump the base image:** change `UPSTREAM_DIGEST` in `Dockerfile.sandbox`, rebuild, re-pin in `blueprint.yaml`, re-run `nemoclaw onboard`.
- **Change config files:** rebuild the image — templates in `/app/openclaw-config/` are baked in. The entrypoint's first-boot check means existing workspaces won't be overwritten; delete the sandbox (`openshell sandbox delete`) and re-onboard to pick up config changes.
- **Rotate Telegram token:** re-export `TELEGRAM_BOT_TOKEN` with the new value and re-run `nemoclaw onboard`. NemoClaw detects the token-hash change, backs up workspace state, rebuilds the sandbox, restores state.

## Troubleshooting

| Symptom | Where to look |
|---|---|
| `Could not resolve openrouter.ai` (or similar) | Check `policy-additions.yaml` — is the endpoint in there and did onboard re-apply? `openshell policy get` |
| Bot doesn't respond | `openshell term` into the sandbox, run `openclaw health`, check `/sandbox/.openclaw-data/openclaw.json` exists and has your real token |
| Chart generation fails with "permission denied" | python3 binary path may not match the `telegram_python` binaries list — check the binary path with `which python3` inside the sandbox and update `policy-additions.yaml` |
| `nemoclaw onboard` rebuilds every time | Expected if `TELEGRAM_BOT_TOKEN` changed. If it rebuilds unexpectedly, `nemoclaw status` shows the current token hash — compare against your env |
| Specialist says "I don't have that command" | `exec-approvals.json` may not include sqlite3/python3 for that agent. Verify inside the sandbox: `cat /sandbox/.openclaw-data/exec-approvals.json` |

## Further reading

- [NemoClaw overview](https://docs.nvidia.com/nemoclaw/latest/about/overview.html)
- [Network policies](https://docs.nvidia.com/nemoclaw/latest/reference/network-policies.html)
- [Sandbox hardening](https://docs.nvidia.com/nemoclaw/latest/deployment/sandbox-hardening.html)
- [Telegram bridge setup](https://docs.nvidia.com/nemoclaw/latest/deployment/set-up-telegram-bridge.html)
