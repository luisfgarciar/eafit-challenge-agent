# EAFIT Challenge — Example Agent

An example AI agent with GitHub MCP integration, deployed as a Verifiable Service on the [Verana](https://verana.io) ecosystem. This is part of the [EAFIT Challenge](https://github.com/verana-labs/eafit-challenge).

## Architecture

This example agent is built with the [hologram-generic-ai-agent-vs](https://github.com/2060-io/hologram-generic-ai-agent-vs) container, which provides a ready-to-use AI chatbot with DIDComm messaging, verifiable credential authentication, and MCP tool integration.

You can find other agent examples (GitHub Agent, Wise Agent, etc.) in the [hologram-verifiable-services](https://github.com/2060-io/hologram-verifiable-services) repository.

This agent is a **child service** of the EAFIT Challenge organization. It:

1. Receives a **Service credential** from the organization (proves it's a legitimate service)
2. Uses the **Avatar credential definition** from `avatar.eafit.testnet.verana.network` to authenticate users via AnonCreds proof requests
3. Provides GitHub MCP tools to authenticated users via encrypted DIDComm chat

## Repository Structure

```
├── config.env              # Service configuration (ports, org URLs, credDef, etc.)
├── deployment.yaml         # Helm chart values for K8s deployment
├── agent-pack.yaml         # Chatbot agent pack (prompts, menus, MCP config)
├── common/
│   └── common.sh           # Shared shell helpers
├── docker/
│   └── docker-compose.yml  # Local development stack
├── scripts/
│   ├── setup.sh            # Local setup (VS Agent + ngrok + Service credential)
│   └── start.sh            # Start Docker Compose stack
├── docs/
│   └── README.md           # User-facing guide
└── .github/
    └── workflows/
        └── deploy.yml      # GitHub Actions workflow for K8s deployment
```

## Local Development

### Prerequisites

- Docker and Docker Compose
- [ngrok](https://ngrok.com/) (authenticated)
- `curl`, `jq`
- An OpenAI API key (or other LLM provider)
- [Hologram Messaging](https://hologram.zone) on your phone
- An **EAFIT Avatar credential** (see below)

The setup script connects to the deployed EAFIT organization at `admin.organization.eafit.testnet.verana.network` to obtain the Service credential. No local organization instance is required.

### Get your EAFIT Avatar Credential

The chatbot uses **credential-based authentication** — you need an EAFIT Avatar credential to test your agent.

1. Open **Hologram Messaging** on your phone
2. Navigate to https://avatar.eafit.testnet.verana.network/
3. Scan the QR code and follow the prompts to obtain your credential

You can verify it works by connecting to the deployed example agent at https://eafit-team-a.eafit.testnet.verana.network/ — scan the QR code, authenticate with your credential, and chat with the bot.

### Quick Start

```bash
# 1. Set up the VS Agent (deploys container, gets Service credential)

set -a
source config.env
set +a
./scripts/setup.sh

# 2. Start the chatbot stack (chatbot + redis + postgres)
export MCP_CONFIG_ENCRYPTION_KEY=$(openssl rand -hex 32)
export ANTHROPIC_API_KEY=sk-...
./scripts/start.sh
```

> Note: if you don't want to use an OPENAI_API_KEY, you can configure any other LLM, refer to [agent pack schema](https://github.com/2060-io/hologram-generic-ai-agent-vs/blob/main/docs/agent-pack-schema.md) for available options.

### Dockerfile and image build

`start.sh` runs `docker compose up` which uses the `Dockerfile` only if the image hasn't been built yet.

- **First run** — Docker builds the image from `Dockerfile` (clones upstream source and applies patches). This takes a few minutes.
- **Subsequent runs** — `start.sh` reuses the cached image and starts immediately.

To force a rebuild (e.g. after changing the Dockerfile or to pick up upstream changes):

```bash
docker compose -f docker/docker-compose.yml build --no-cache chatbot
```

### Connect with Hologram (local)

Once the stack is running, open the VS Agent QR code in your browser and scan it with Hologram Messaging:

```
http://localhost:3010/v1/qr
```

> Port `3010` is the VS Agent admin port (`VS_AGENT_ADMIN_PORT` in `ids.env`). Open the URL in a browser, scan the QR code with Hologram, and the agent will send you a greeting.

## Kubernetes Deployment (GitHub Actions)

The `.github/workflows/deploy.yml` workflow deploys the agent to the shared EAFIT Challenge K8s cluster.

### Required GitHub Secrets

| Secret | Description |
| ------ | ----------- |
| `OVH_KUBECONFIG` | Kubeconfig for the K8s cluster |
| `K8S_NAMESPACE` | Target namespace (ideally, use your team name) |
| `EXAMPLE_AGENT_OPENAI_API_KEY` | OpenAI API key for the chatbot |
| `EXAMPLE_AGENT_POSTGRES_PASSWORD` | PostgreSQL password |
| `EXAMPLE_AGENT_MCP_CONFIG_ENCRYPTION_KEY` | Encryption key for MCP user configs (generate with `openssl rand -hex 32`) |
| `EXAMPLE_AGENT_WALLET_KEY` | VS Agent wallet encryption key (generate with `openssl rand -base64 32`) |
| `EXAMPLE_AGENT_VSAGENT_DB_PASSWORD` | VS Agent internal DB password |

### Deployment

Run the workflow from the GitHub Actions tab with step `all` to deploy and obtain credentials.

The agent will be available at the URL configured in `AGENT_PUBLIC_URL` (see below).

## Configuration

Key settings in `config.env`:

- **`AGENT_PUBLIC_URL`** — Public URL of the deployed agent. For student teams, use the convention: `https://<agentname>.agents.<team_name>.teams.eafit.testnet.verana.network`
- **`CREDENTIAL_DEFINITION_ID`** — AnonCreds credDef from the EAFIT Avatar service (hardcoded)
- **`ORG_VS_PUBLIC_URL`** — Public URL of the EAFIT organization agent
- **`SERVICE_NAME`** — Display name shown in the Service credential
- **`OPENAI_MODEL`** — LLM model for the chatbot

## License

Apache-2.0
