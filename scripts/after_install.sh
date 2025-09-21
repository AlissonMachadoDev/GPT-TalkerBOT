#!/bin/bash

# Exit on error and print commands
set -e
set -x

echo "Starting after_install script..."

# Set timeout for the entire script (30 minutes)
TIMEOUT=1800
SCRIPT_START=$SECONDS

check_timeout() {
  if [ $((SECONDS - SCRIPT_START)) -gt $TIMEOUT ]; then
    echo "Script timed out after 30 minutes"
    exit 1
  fi
}

setup_environment() {
  export HOME="/home/ubuntu"
  export MIX_ENV=prod
  export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"

  if [ ! -f "$HOME/.asdf/asdf.sh" ]; then
    echo "FATAL: asdf.sh not found"
    exit 1
  fi

  source "$HOME/.asdf/asdf.sh"
  cd "$APP_DIR" || {
    echo "FATAL: Cannot cd to $APP_DIR"
    exit 1
  }
}

# Install hex and rebar with timeout
echo "Installing hex and rebar..."
if ! timeout 60 asdf exec mix local.hex --force; then
  echo "Failed to install hex"
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
if ! asdf exec mix release --overwrite; then
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
