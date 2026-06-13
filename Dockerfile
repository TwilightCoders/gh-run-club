# gh-run-club — one container, many repo-scoped GitHub Actions runner agents.
# Lean/generic on purpose: need cmake/Electron/etc? Extend this image
#   FROM ghcr.io/twilightcoders/gh-run-club:latest
#   USER root ; RUN apt-get update && apt-get install -y … ; USER runner
FROM ubuntu:22.04
ARG RUNNER_VERSION=2.335.1
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl jq git sudo tar gzip \
 && rm -rf /var/lib/apt/lists/*
# Non-root runner with passwordless sudo (so workflows can apt-install)
RUN useradd -m -s /bin/bash runner \
 && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner
# Stage the runner once; every agent copies from here into its own dir.
RUN mkdir -p /opt/actions-runner && cd /opt/actions-runner \
 && curl -fsSL -o runner.tgz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && tar xzf runner.tgz && rm runner.tgz \
 && ./bin/installdependencies.sh \
 && chown -R runner:runner /opt/actions-runner
# Pre-create the per-agent dir owned by 'runner'. A named volume mounted here
# inherits this ownership when first populated, so the non-root runner can write
# its agent dirs + persisted credentials.
RUN mkdir -p /home/runner/agents && chown runner:runner /home/runner/agents
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# 0755 (not +x): a #! script must be *readable* by the user that execs it. The
# build context file may arrive 0700 (owner-only); +x alone leaves non-root
# 'runner' with execute-but-not-read -> "Permission denied" at container start.
RUN chmod 0755 /usr/local/bin/entrypoint.sh
USER runner
WORKDIR /home/runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
