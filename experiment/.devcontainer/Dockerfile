FROM node:20-bookworm

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

RUN apt-get update && apt-get install -y --no-install-recommends \
  aggregate \
  ca-certificates \
  curl \
  dnsutils \
  git \
  iproute2 \
  ipset \
  iptables \
  jq \
  less \
  procps \
  sudo \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV DEVCONTAINER=true
ENV SHELL=/bin/bash

RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

# Claude Code CLI
USER root
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Firewall + sudo for node user
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY ensure-claude-perm-skip.sh /usr/local/bin/ensure-claude-perm-skip.sh
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/ensure-claude-perm-skip.sh && \
  echo "node ALL=(root) NOPASSWD: ALL" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

# Python (for agent scripts)
RUN rm -f /usr/lib/python3.11/EXTERNALLY-MANAGED && \
  curl -sS https://bootstrap.pypa.io/get-pip.py | python3

USER node
