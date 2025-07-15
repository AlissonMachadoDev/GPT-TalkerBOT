#!/bin/bash
# Is this running?
systemctl restart gpt_talkerbot.service

sleep 10

systemctl is-active gpt_talkerbot.service

# Is this answering?
timeout 30 bash -c 'until printf "" 2>>/dev/null >>/dev/tcp/localhost/4000; do sleep 1; done'


exit 0