# gh-run-club

> The first rule of gh-run-club: you *do* talk about gh-run-club. (It's open source.)

**One container, many [self-hosted GitHub Actions runner](https://docs.github.com/actions/hosting-your-own-runners) agents** — one per repo, from a single `REPOS` list and a single token.

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
    env_file: .env            # ACCESS_TOKEN=<PAT>
    environment:
      ORG: your-org
      REPOS: "repo-a repo-b repo-c"
      LABELS: "self-hosted,linux,x64"
      RUNNER_NAME_PREFIX: $(hostname)
```

```sh
echo 'ACCESS_TOKEN=github_pat_xxx' > .env   # fine-grained PAT, Administration: R/W on those repos
docker compose up -d
```

Each repo gets an agent named `<prefix>-<repo>`, labelled per `LABELS`, with its own `_work` dir. The PAT mints a fresh registration token per agent at startup, so the container **survives recreate** (no single-use tokens to refresh).

## Configuration

| Env | Required | Default | Meaning |
|---|---|---|---|
| `ORG` | ✓ | — | GitHub org/user that owns the repos |
| `REPOS` | ✓ | — | Space-separated repo names under `ORG` |
| `ACCESS_TOKEN` | ✓ | — | Fine-grained PAT, **Administration: read+write** on each repo |
| `LABELS` | | `self-hosted,linux,x64` | Runner labels (`runs-on:` targets these) |
| `RUNNER_NAME_PREFIX` | | hostname | Agent names become `<prefix>-<repo>` |

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

`entrypoint.sh` loops over `$REPOS`: copies the staged runner into a per-repo dir, mints a registration token from the PAT via the REST API, `config.sh`s an agent, and backgrounds `run.sh`. `SIGTERM` deregisters every agent. If any agent exits, the container tears down so your orchestrator (`restart: unless-stopped`) brings it back fresh.

> One agent per repo means a runner dist is copied per repo (~a few hundred MB each). Fine for a handful of repos; if you run dozens, weigh org runners (Team) instead.

## License

MIT — see [LICENSE](LICENSE).
