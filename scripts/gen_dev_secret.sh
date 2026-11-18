#!/bin/bash
set -euo pipefail

get_param() {
  aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text
}

# Como get_param, mas devolve "" em vez de falhar quando o parâmetro não existe
# (usado para os opcionais, que podem não estar no SSM ainda)
get_param_optional() {
  aws ssm get-parameter --name "$1" --with-decryption --query Parameter.Value --output text 2>/dev/null || echo ""
}

echo "Buscando parâmetros do SSM..."

OPENAI_API_KEY=$(get_param "/gpt_talkerbot/prod/openai_api_key")
GROK_API_KEY=$(get_param "/gpt_talkerbot/prod/grok_api_key")
TELEGRAM_API_KEY=$(get_param "/gpt_talkerbot/prod/telegram_api_key")
TELEGRAM_WEBHOOK_SECRET=$(get_param "/gpt_talkerbot/prod/telegram_webhook_secret")
SERVER_HOST=$(get_param "/gpt_talkerbot/prod/server_host")
DATABASE_URL=$(get_param "/gpt_talkerbot/prod/database_url")
OWNER_ID=$(get_param "/gpt_talkerbot/prod/owner_id")
ALLOWED_GROUPS=$(get_param "/gpt_talkerbot/prod/allowed_groups")
DEFAULT_PROMPT=$(get_param "/gpt_talkerbot/prod/default_prompt")
TTS_PROVIDER=$(get_param_optional "/gpt_talkerbot/prod/tts_provider")
ELEVENLABS_API_KEY=$(get_param_optional "/gpt_talkerbot/prod/elevenlabs_api_key")
ELEVENLABS_VOICES=$(get_param_optional "/gpt_talkerbot/prod/elevenlabs_voices")
FISH_API_KEY=$(get_param_optional "/gpt_talkerbot/prod/fish_api_key")
FISH_VOICES=$(get_param_optional "/gpt_talkerbot/prod/fish_voices")

# Converte "id1,id2,id3" para [id1, id2, id3]
ALLOWED_GROUPS_ELIXIR="[$(echo "$ALLOWED_GROUPS" | sed 's/,/, /g')]"

# Escapa aspas duplas para strings Elixir
DEFAULT_PROMPT_ESCAPED=$(echo "$DEFAULT_PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g')

cat > config/dev.secret.exs << ELIXIR
import Config

config :gpt_talkerbot, :openai_api_key, "$OPENAI_API_KEY"
config :gpt_talkerbot, :grok_api_key, "$GROK_API_KEY"
config :gpt_talkerbot, :telegram_api_key, "$TELEGRAM_API_KEY"
config :gpt_talkerbot, :telegram_webhook_secret, "$TELEGRAM_WEBHOOK_SECRET"
config :gpt_talkerbot, :server_host, "$SERVER_HOST"
config :gpt_talkerbot, :owner_id, "$OWNER_ID"
config :gpt_talkerbot, :allowed_groups, $ALLOWED_GROUPS_ELIXIR
config :gpt_talkerbot, :default_prompt, "$DEFAULT_PROMPT_ESCAPED"
config :gpt_talkerbot, :tts_provider, "${TTS_PROVIDER:-openai}"
config :gpt_talkerbot, :elevenlabs_api_key, "$ELEVENLABS_API_KEY"
config :gpt_talkerbot, :elevenlabs_voices, "$ELEVENLABS_VOICES"
config :gpt_talkerbot, :fish_api_key, "$FISH_API_KEY"
config :gpt_talkerbot, :fish_voices, "$FISH_VOICES"
ELIXIR

# No Ecto desta versão a :url vence hostname/port. A URL de produção usa
# localhost, que nesta máquina é outro Postgres; o app de dev entra pelo túnel.
python3 - "$DATABASE_URL" "$SERVER_HOST" << 'PY'
import os
import sys
import urllib.parse

url = sys.argv[1]
server_host = sys.argv[2]
parsed = urllib.parse.urlparse(url)
database = (parsed.path or "").lstrip("/").split("?")[0]

if not parsed.hostname or not parsed.username or not database:
    sys.stderr.write("DATABASE_URL inválida (esperado ecto://user:pass@host/db)\n")
    sys.exit(1)

def elixir_string(value):
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("#{", "\\#{")
    )
    return f'"{escaped}"'

remote_port = parsed.port or 5432
password = urllib.parse.unquote(parsed.password or "")
username = urllib.parse.unquote(parsed.username)
connect_host = parsed.hostname
connect_port = remote_port
tunnel_path = "config/dev.db_tunnel"

# No servidor a URL usa localhost. Da máquina de dev essa porta é outro Postgres.
# O dev_up.sh abre um túnel SSH e o app entra por 127.0.0.1:15432, sem migrar.
if parsed.hostname in ("localhost", "127.0.0.1", "::1"):
    ssh_host = urllib.parse.urlparse(server_host).hostname
    if not ssh_host:
        sys.stderr.write("server_host sem hostname; não dá para abrir o túnel do Postgres\n")
        sys.exit(1)
    connect_host = "127.0.0.1"
    connect_port = 15432
    with open(tunnel_path, "w", encoding="utf-8") as tunnel:
        tunnel.write(
            "ssh_user=ubuntu\n"
            f"ssh_host={ssh_host}\n"
            f"remote_port={remote_port}\n"
            f"local_port={connect_port}\n"
        )
    userinfo = urllib.parse.quote(username, safe="")
    if parsed.password is not None:
        userinfo += ":" + urllib.parse.quote(password, safe="")
    connect_url = urllib.parse.urlunparse(
        parsed._replace(netloc=f"{userinfo}@{connect_host}:{connect_port}")
    )
else:
    connect_url = url
    try:
        os.remove(tunnel_path)
    except FileNotFoundError:
        pass

with open("config/dev.secret.exs", "a", encoding="utf-8") as secret:
    secret.write(
        "\n"
        "config :gpt_talkerbot, GptTalkerbot.Repo,\n"
        f"  url: {elixir_string(connect_url)},\n"
        f"  username: {elixir_string(username)},\n"
        f"  password: {elixir_string(password)},\n"
        f"  hostname: {elixir_string(connect_host)},\n"
        f"  port: {connect_port},\n"
        f"  database: {elixir_string(database)},\n"
        "  ssl: false\n"
    )
PY

DB_HOST=$(python3 - "$DATABASE_URL" << 'PY'
import sys, urllib.parse
print(urllib.parse.urlparse(sys.argv[1]).hostname or "")
PY
)

echo "config/dev.secret.exs criado com sucesso!"
echo "Postgres de dev: ${DB_HOST} (servidor remoto)"
