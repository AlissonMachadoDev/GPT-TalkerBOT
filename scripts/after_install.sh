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
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    install_nodejs
    check_timeout
fi

# Verify development tools
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# Source asdf with error checking
if [ -f "$HOME/.asdf/asdf.sh" ]; then
    source "$HOME/.asdf/asdf.sh" || {
        echo "Failed to source asdf.sh"
        exit 1
    }
    echo "Sourced asdf.sh"
else
    echo "Error: asdf.sh not found"
    exit 1
fi

# Check required tools
for cmd in erl elixir mix; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd not found"
        exit 1
    fi
done

# Navigate to application directory
cd /opt/gpt_talkerbot || {
    echo "Failed to change to application directory"
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
if ! rebar3 --version; then
    echo "rebar3 installation verification failed"
    exit 1
fi

# Install hex and rebar with timeout
echo "Installing hex and rebar..."
if ! timeout 60 mix local.hex --force; then
    echo "Failed to install hex"
    exit 1
fi
if ! timeout 60 mix local.rebar --force; then
    echo "Failed to install rebar"
    exit 1
fi

# Get dependencies with timeout
echo "Getting dependencies..."
if ! timeout 300 mix deps.get --only prod; then
    echo "Failed to get dependencies"
    exit 1
fi
check_timeout

# Install node dependencies
echo "Installing node dependencies..."
cd assets || exit 1
if [ ! -f "package.json" ]; then
    echo "Error: package.json not found in $(pwd)"
    exit 1
fi
if ! timeout 300 npm install --legacy-peer-deps; then
    echo "npm install failed"
    exit 1
fi
cd .. || exit 1
check_timeout

# Compile and deploy assets with timeout
echo "Compiling and deploying assets..."
if ! timeout 300 mix compile; then
    echo "mix compile failed"
    exit 1
fi
if ! timeout 300 mix assets.deploy; then
    echo "mix assets.deploy failed"
    exit 1
fi
check_timeout

# Create production release with timeout
echo "Creating production release..."
if ! timeout 300 mix release --overwrite; then
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