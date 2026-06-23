#!/bin/bash
set -euo pipefail

get_param() {
  aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text
}

echo "Buscando parâmetros do SSM..."

OPENAI_API_KEY=$(get_param "/gpt_talkerbot/prod/openai_api_key")
GROK_API_KEY=$(get_param "/gpt_talkerbot/prod/grok_api_key")
TELEGRAM_API_KEY=$(get_param "/gpt_talkerbot/prod/telegram_api_key")
OWNER_ID=$(get_param "/gpt_talkerbot/prod/owner_id")
ALLOWED_GROUPS=$(get_param "/gpt_talkerbot/prod/allowed_groups")
DEFAULT_PROMPT=$(get_param "/gpt_talkerbot/prod/default_prompt")

# Converte "id1,id2,id3" para [id1, id2, id3]
ALLOWED_GROUPS_ELIXIR="[$(echo "$ALLOWED_GROUPS" | sed 's/,/, /g')]"

# Escapa aspas duplas para strings Elixir
DEFAULT_PROMPT_ESCAPED=$(echo "$DEFAULT_PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g')

cat > config/dev.secret.exs << ELIXIR
import Config

config :gpt_talkerbot, :openai_api_key, "$OPENAI_API_KEY"
config :gpt_talkerbot, :grok_api_key, "$GROK_API_KEY"
config :gpt_talkerbot, :telegram_api_key, "$TELEGRAM_API_KEY"
config :gpt_talkerbot, :owner_id, "$OWNER_ID"
config :gpt_talkerbot, :allowed_groups, $ALLOWED_GROUPS_ELIXIR
config :gpt_talkerbot, :default_prompt, "$DEFAULT_PROMPT_ESCAPED"
ELIXIR

echo "config/dev.secret.exs criado com sucesso!"
