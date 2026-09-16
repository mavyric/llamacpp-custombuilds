# Stage 1: Build environment
FROM rocm/dev-ubuntu-24.04:latest AS builder

ARG PRS_TO_MERGE=""
ARG EXTRA_REMOTES=""
ARG AMDGPU_TARGET="gfx1201"

# Force Docker to use bash for all subsequent RUN commands
SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake ninja-build build-essential ca-certificates libnuma-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Clone latest upstream master
RUN git clone https://github.com/ggml-org/llama.cpp.git llama.cpp
WORKDIR /workspace/llama.cpp

RUN git config user.email "bot@ci.local" && git config user.name "CI Builder"

# Dynamically fetch and merge requested PRs
RUN if [ -n "$PRS_TO_MERGE" ]; then \
      for pr in $(echo "$PRS_TO_MERGE" | tr ',' ' '); do \
        echo "==> Fetching and merging upstream PR #${pr}..."; \
        git fetch origin pull/${pr}/head:pr-${pr} && \
        git merge --no-edit pr-${pr}; \
      done; \
    fi

# Dynamically fetch and cherry-pick external repo branches
RUN if [ -n "$EXTRA_REMOTES" ]; then \
      REPO_URL=$(echo "$EXTRA_REMOTES" | cut -d'@' -f1); \
      REPO_BRANCH=$(echo "$EXTRA_REMOTES" | cut -d'@' -f2); \
