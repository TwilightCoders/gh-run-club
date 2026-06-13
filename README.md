# gh-run-club

> The first rule of gh-run-club: you *do* talk about gh-run-club. (It's open source.)

**One container, many [self-hosted GitHub Actions runner](https://docs.github.com/actions/hosting-your-own-runners) agents** — one per repo, from a single `REPOS` list. No PAT required: register each agent with a short-lived token and the credentials persist.

## Why

GitHub's self-hosted runner model leaves a gap:

- **`runs-on` repo runners** bind one runner registration to one repo.
- **Org-level runners** (one runner → many repos) require **GitHub Team/Enterprise** — on a **Free** org they won't serve private repos.
- The popular [`myoung34/github-runner`](https://github.com/myoung34/docker-github-runner) image is **one agent per container** → N repos = N containers to babysit.

gh-run-club runs **N repo-scoped agents inside one container**, so a Free org / homelab box can serve many private repos from a single image and a single managed unit. Add a repo = one word in `REPOS`.

## Quick start

```yaml
# docker-compose.yml
services:
  runners:
    image: ghcr.io/twilightcoders/gh-run-club:latest
    restart: unless-stopped
    env_file: .env            # REG_TOKEN_<REPO> per repo  (or ACCESS_TOKEN=<PAT>)
    environment:
      ORG: your-org
      REPOS: "repo-a repo-b repo-c"
      LABELS: "self-hosted,linux,x64"
      RUNNER_NAME_PREFIX: $(hostname)
    volumes:
      - gh-run-club-agents:/home/runner/agents   # persists registrations
volumes:
  gh-run-club-agents:
```

Mint one short-lived registration token per repo and drop them in `.env`:

```sh
for r in repo-a repo-b repo-c; do
  key="REG_TOKEN_$(echo "$r" | tr 'a-z-' 'A-Z_')"
  tok=$(gh api -X POST repos/your-org/$r/actions/runners/registration-token --jq .token)
  echo "$key=$tok"
done > .env
docker compose up -d
```

Each repo gets an agent named `<prefix>-<repo>`, labelled per `LABELS`, with its own `_work` dir. Agents register **once**; their credentials persist in the `gh-run-club-agents` volume and are reused on every restart/reboot — the tokens are spent after first boot, and **no admin credential lives on the host**.

> Recreate-resilient variant: instead of `REG_TOKEN_*`, set `ACCESS_TOKEN` to a fine-grained PAT (repo **Administration: R/W**) and the container mints/refreshes registration tokens itself on every boot — at the cost of keeping a durable admin credential on the host. Pick whichever trade-off you prefer.

## Configuration

| Env | Required | Default | Meaning |
|---|---|---|---|
| `ORG` | ✓ | — | GitHub org/user that owns the repos |
| `REPOS` | ✓ | — | Space-separated repo names under `ORG` |
| `REG_TOKEN_<REPO>` | ✓¹ | — | Short-lived registration token for that repo (repo name uppercased, non-alphanumerics → `_`). Used once; ignored after creds persist. |
| `ACCESS_TOKEN` | ✓¹ | — | Alternative to `REG_TOKEN_*`: fine-grained PAT, **Administration: read+write** on each repo |
| `LABELS` | | `self-hosted,linux,x64` | Runner labels (`runs-on:` targets these) |
| `RUNNER_NAME_PREFIX` | | hostname | Agent names become `<prefix>-<repo>` |
| `AGENTS_DIR` | | `$HOME/agents` | Where per-agent dirs + persisted creds live (mount as a volume) |

¹ Provide **either** a `REG_TOKEN_<REPO>` per repo (token-only) **or** a single `ACCESS_TOKEN` (PAT). `REG_TOKEN_<REPO>` wins when both are set. Neither is needed once an agent's credentials are already persisted in `AGENTS_DIR`.

## Extending the image

The base is intentionally **lean** (just the runner + git/curl/jq/sudo). Need a toolchain? Layer on top:

```dockerfile
FROM ghcr.io/twilightcoders/gh-run-club:latest
USER root
RUN apt-get update && apt-get install -y --no-install-recommends cmake libuv1-dev xvfb && rm -rf /var/lib/apt/lists/*
USER runner
```

## Security

⚠️ **Private repos only.** A self-hosted runner reachable by a **public** repo lets fork-PR workflows run arbitrary code on your host/LAN. Don't point gh-run-club at public repos (or untrusted fork PRs). The container runs the agents as a non-root `runner` user with passwordless sudo (for in-workflow `apt`); no Docker socket is mounted.

## How it works

`entrypoint.sh` loops over `$REPOS`. For each repo, if persisted credentials already exist in `AGENTS_DIR` it just backgrounds `run.sh`; otherwise it copies the staged runner into a per-repo dir, registers via `config.sh` using that repo's `REG_TOKEN_<REPO>` (or a token minted from `ACCESS_TOKEN`), and backgrounds `run.sh`. On `SIGTERM`: in PAT mode it deregisters every agent; in token-only mode it leaves them registered so the persisted credentials are reused next start. If any agent exits, the container tears down so your orchestrator (`restart: unless-stopped`) brings it back.

> One agent per repo means a runner dist is copied per repo (~a few hundred MB each). Fine for a handful of repos; if you run dozens, weigh org runners (Team) instead.

## License

MIT — see [LICENSE](LICENSE).
