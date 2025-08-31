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
export PATH="$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
export ASDF_DATA_DIR="$HOME/.asdf"
export ASDF_DIR="$HOME/.asdf"
if [ -f "$HOME/.asdf/asdf.sh" ]; then
  . "$HOME/.asdf/asdf.sh"
else
  echo "Error: asdf.sh not found"
  exit 1
fi

echo "Installing Erlang build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y build-essential autoconf m4 libncurses5-dev libssl-dev

cd /opt/gpt_talkerbot || {
  echo "Failed to change to application directory"
  exit 1
}
asdf plugin add erlang || true
asdf plugin add elixir || true
if ! asdf install; then
  echo "asdf install failed"
  ls -la ~/.asdf/plugins/erlang/logs/ || echo "No build logs"
  exit 1
fi
asdf reshim erlang
asdf reshim elixir
asdf current

for cmd in erl elixir mix; do
  command -v "$cmd" >/dev/null || {
    echo "Error: $cmd not found"
    exit 1
  }
done

asdf current
echo "which erl: $(command -v erl)"
echo "which elixir: $(command -v elixir)"
asdf which erl || true
asdf which elixir || true
asdf exec elixir -v || {
  echo "Elixir via asdf não está ativo"
  exit 1
}
check_timeout

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
