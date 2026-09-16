# Stage 1: Build environment
FROM rocm/dev-ubuntu-24.04:latest AS builder

ARG PRS_TO_MERGE=""
ARG EXTRA_REMOTES=""
ARG AMDGPU_TARGET="gfx1201"

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
      IFS=',' read -ra PRS <<< "$PRS_TO_MERGE"; \
      for pr in "${PRS[@]}"; do \
        echo "==> Fetching and merging upstream PR #${pr}..."; \
        git fetch origin pull/${pr}/head:pr-${pr} && \
        git merge --no-edit pr-${pr}; \
      done; \
    fi

# Dynamically fetch and cherry-pick external repo branches
RUN if [ -n "$EXTRA_REMOTES" ]; then \
      REPO_URL=$(echo "$EXTRA_REMOTES" | cut -d'@' -f1); \
      REPO_BRANCH=$(echo "$EXTRA_REMOTES" | cut -d'@' -f2); \
      echo "==> Fetching external remote: ${REPO_URL} (${REPO_BRANCH})..."; \
      git remote add extra "${REPO_URL}" && \
      git fetch extra "${REPO_BRANCH}" && \
      git cherry-pick extra/"${REPO_BRANCH}" || true; \
    fi

# Compile static binary for target GPU
RUN cmake -B build -G Ninja \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS="${AMDGPU_TARGET}" \
        -DGGML_HIP_ROCWMMA_FATTN=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DGGML_BUILD_TESTS=OFF \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release --target llama-server -j$(nproc)

# Stage 2: Runtime image
FROM rocm/dev-ubuntu-24.04:latest

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    numactl ca-certificates curl jq && \
    rm -rf /var/lib/apt/lists/*

# Copy compiled standalone binary
COPY --from=builder /workspace/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server

# Install llama-swap
RUN LLAMASWAP_VER=$(curl -s https://api.github.com/repos/mostlygeek/llama-swap/releases/latest | jq -r .tag_name | tr -d 'v') && \
    curl -fsSL -o /tmp/llama-swap.tar.gz "https://github.com/mostlygeek/llama-swap/releases/download/v${LLAMASWAP_VER}/llama-swap_${LLAMASWAP_VER}_linux_amd64.tar.gz" && \
    tar -xzf /tmp/llama-swap.tar.gz -C /usr/local/bin/ llama-swap && \
    rm /tmp/llama-swap.tar.gz

WORKDIR /app
EXPOSE 8011

ENTRYPOINT ["llama-swap"]
CMD ["-config", "/etc/llama-swap/config.yaml", "-listen", "0.0.0.0:8011"]
