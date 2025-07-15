#!/bin/bash
# Gracefully stop the application
if [ -f /opt/gpt_talkerbot/gpt_talkerbot/bin/gpt_talkerbot ]; then
    /opt/gpt_talkerbot/gpt_talkerbot/bin/gpt_talkerbot stop
fi