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
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
USER runner
WORKDIR /home/runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
