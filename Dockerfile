FROM vllm/vllm-openai:v0.6.0

# Disable interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies, OpenSSH for direct access, and Tailscale
RUN apt-get update -qq && apt-get install -y -qq \
    curl \
    jq \
    iproute2 \
    ca-certificates \
    openssh-server \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH daemon directory structure
RUN mkdir -p /var/run/sshd && \
    mkdir -p /root/.ssh && \
    chmod 700 /root/.ssh

# Copy your start script from local hierarchy into container root
COPY runpod/start.sh /start.sh
RUN chmod +x /start.sh

# Override the default vLLM entrypoint so your script becomes PID 1
ENTRYPOINT ["/bin/bash", "-lc", "exec /start.sh"]