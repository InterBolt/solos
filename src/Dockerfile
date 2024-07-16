FROM debian:latest

SHELL ["/bin/bash", "-c"]

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --assume-yes --no-install-recommends \
  git-all \
  coreutils \
  bash-completion \
  ca-certificates \
  man-db \
  curl \
  jq \
  wget \
  sudo \
  manpages-dev \
  keychain \
  procps \
  firejail \
  gpg \
  rsync \
  python3.11 python3-pip python3.11-venv

# Install mkdocs
RUN python3.11 -m venv .venv && ./.venv/bin/python -m pip install mkdocs mkdocs-material

# Install GitHub CLI
RUN sudo mkdir -p -m 755 /etc/apt/keyrings \
  && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh -y

# Make logs pretty
ENV TERM=xterm-256color

# Add gum for bash prompting
# https://github.com/charmbracelet/gum
RUN sudo mkdir -p /etc/apt/keyrings \ 
  && curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list \
  && sudo apt update && sudo apt install gum

# Docker - CLI only
RUN sudo apt-get remove docker.io \
  && sudo apt-get remove docker-doc \
  && sudo apt-get remove docker-compose \
  && sudo apt-get remove podman-docker \
  && sudo apt-get remove containerd \
  && sudo apt-get remove runc \
  && install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list >/dev/null \
  && apt-get update \
  && apt-get install docker-ce-cli docker-buildx-plugin -y