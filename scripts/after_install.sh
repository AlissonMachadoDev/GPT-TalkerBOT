#!/bin/bash

# Exit on error and print commands
set -e
set -x

echo "Starting after_install script..."

# Set timeout for the entire script (30 minutes)
TIMEOUT=600
SCRIPT_START=$SECONDS

check_timeout() {
  if [ $((SECONDS - SCRIPT_START)) -gt $TIMEOUT ]; then
    echo "Script timed out after 30 minutes"
    exit 1
  fi
}

# Export environment variables with error checking
export HOME="/home/ubuntu"
export MIX_ENV=prod
export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"
export ASDF_DIR="$HOME/.asdf"
if [ -f "$HOME/.asdf/asdf.sh" ]; then
  . "$HOME/.asdf/asdf.sh"
else
  echo "Error: asdf.sh not found"
  exit 1
fi

# Function to install Node.js with timeout
install_nodejs() {
  echo "Installing Node.js..."

  # 5-minute timeout for Node.js installation
  if ! timeout 300 bash -c '
        sudo apt-get update &&
        sudo apt-get install -y ca-certificates curl gnupg &&
        sudo mkdir -p /etc/apt/keyrings &&
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg &&
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list &&
        sudo apt-get update &&
        sudo apt-get install -y nodejs
    '; then
    echo "Node.js installation timed out or failed"
    exit 1
  fi

  # Verify installation
  if ! node --version; then
    echo "Node.js installation verification failed"
    exit 1
  fi
  if ! npm --version; then
    echo "npm installation verification failed"
    exit 1
  fi

  echo "Node.js installation completed"
}

# Install Node.js if needed (with timeout check)
if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
  install_nodejs
  check_timeout
fi

# Verify development tools
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# Check required tools
for cmd in erl elixir mix; do
  if ! command -v $cmd &>/dev/null; then
    echo "Error: $cmd not found"
    exit 1
  fi
done

# Navigate to application directory
cd /opt/gpt_talkerbot || {
  echo "Failed to change to application directory"
  exit 1
}

asdf plugin add erlang || true
asdf plugin add elixir || true
asdf install
asdf current
elixir -v || {
  echo "Elixir via asdf não está ativo"
  exit 1
}

# Install rebar3 with timeout
timeout 60 bash -c '
    wget https://s3.amazonaws.com/rebar3/rebar3 &&
    chmod +x rebar3 &&
    sudo mv rebar3 /usr/local/bin/
' || {
  echo "Failed to install rebar3"
  exit 1
}

# Verify rebar3
if ! asdf exec rebar3 --version; then
  echo "rebar3 installation verification failed"
  exit 1
fi

# Install hex and rebar with timeout
echo "Installing hex and rebar..."
if ! timeout 60 asdf exec mix local.hex --force; then
  echo "Failed to install hex"
  exit 1
fi
if ! timeout 60 asdf exec mix local.rebar --force; then
  echo "Failed to install rebar"
  exit 1
fi

# Get dependencies with timeout
echo "Getting dependencies..."
if ! timeout 300 asdf exec mix deps.get --only prod; then
  echo "Failed to get dependencies"
  exit 1
fi
check_timeout

# Create production release with timeout
echo "Creating production release..."
if ! timeout 300 asdf exec mix release --overwrite; then
  echo "Release creation failed"
  exit 1
fi

# Verify release
if [ ! -f "_build/prod/rel/gpt_talkerbot/bin/gpt_talkerbot" ]; then
  echo "Error: Release binary not found"
  exit 1
fi

DURATION=$((SECONDS - SCRIPT_START))
echo "After install script completed successfully in $DURATION seconds"
exit 0
