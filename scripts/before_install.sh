#!/bin/bash
set -e  # Exit on error

echo "Starting cleanup process..."

# Stop the application if it's running
if [ -f /opt/gpt_talkerbot/gpt_talkerbot/bin/gpt_talkerbot ]; then
    echo "Stopping existing application..."
    /opt/gpt_talkerbot/gpt_talkerbot/bin/gpt_talkerbot stop || true
fi

# Make sure the directory exists
echo "Ensuring directory exists..."
mkdir -p /opt/gpt_talkerbot

# Clean up thoroughly
echo "Cleaning up old deployment..."
rm -rf /opt/gpt_talkerbot/*
rm -rf /opt/gpt_talkerbot/.[!.]*  # Remove hidden files too

# Reset permissions
echo "Setting up permissions..."
chown -R ubuntu:ubuntu /opt/gpt_talkerbot
chmod -R 755 /opt/gpt_talkerbot

echo "Before install script completed successfully"
exit 0