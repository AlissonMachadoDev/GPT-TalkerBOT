# Ratobô 🐀

Bot de humor para grupos de Telegram: um rato robótico que mora no porão dos
servidores, responde quando chamado, se intromete quando ninguém pediu e guarda
rancor (e fatos) sobre os usuários.

## Arquitetura

```
Telegram ──webhook──> Phoenix (BotController)
                          │  valida secret token, permissões e gatilhos
                          ▼
                      RabbitMQ ──> Broadway (BotProcessor)
                                       │
                                       ▼
                                 MessageHandler
                                  │ SpiceChecker roteia OpenAI/Grok
                                  │ Personality + mood + fatos + contexto do grupo
                                  ▼
                                 resposta no chat
```

Módulos principais:

| Módulo | Papel |
|---|---|
| `RuntimeEnvs` | Config de runtime via AWS SSM (refresh 12h), leitura por `:persistent_term` |
| `LLM` | Ponto único de acesso a OpenAI/Grok (modelos configuráveis) |
| `MoodTracker` | Humor por chat: insulto → grumpy, rajada → excited, madrugada → sleepy, decay p/ normal |
| `Memory` | Histórico de conversa (filtrado por embeddings) + fatos por usuário (máx. 20) |
| `GroupMessageCache` + `GroupContextExtractor` | Buffer do grupo → resumo de contexto via LLM |
| `Interjector` | Intromissão espontânea (probabilidade + cooldown por chat) |
| `Reactor` | Reações de emoji aleatórias a mensagens do grupo |
| `DailySummary` | Resumo do dia debochado postado no horário configurado |

## Gatilhos

- Mensagem contendo "ratobô" (regex `rato\s*b[oôóò]t?`) em chat permitido.
- Respostas (reply) às mensagens do bot **não** disparam resposta — de
  propósito, para permitir marcar uma mensagem dele sem provocá-lo.

## Comandos

Público (chats permitidos): `/humor`, `/fatos`, `/esquece`, `/resumo`.

Admin (apenas owner): `/setproduction`, `/updatevariables`, `/setgrok`, `/setopenai`,
`/cleardatabase` (apaga toda a memória do bot — conversas, fatos, contextos e humores;
tabelas legadas de registro ficam intactas).

Legado: `/register`, `/register_group`.

## Configuração

Env vars (prod): `DATABASE_URL`, `SECRET_KEY_BASE`, `OPENAI_API_KEY`,
`GROK_API_KEY`, `TELEGRAM_API_KEY`, `SERVER_HOST`, `TELEGRAM_WEBHOOK_SECRET`,
`RABBITMQ_HOST`, `RABBITMQ_USERNAME`, `RABBITMQ_PASSWORD`, credenciais AWS.

Parâmetros no SSM (path `/gpt_talkerbot/prod/`), atualizáveis sem deploy via
`/updatevariables`: `default_prompt`, `owner_id`, `allowed_users`,
`allowed_groups`, `user_labels`, `spice_threshold`, `temperature`,
`grok_reasoning`, `openai_model`, `grok_model`, `relevance_threshold`,
`always_include_last`, `max_context_messages`, `session_gap_minutes`,
`mood_duration`, `interject_probability`, `interject_cooldown_minutes`,
`reaction_probability`, `daily_summary_hour` (fora de 0–23 desativa),
`utc_offset`.

Acesso é *fail closed*: com `allowed_users` e `allowed_groups` vazios o bot
não responde a ninguém.

`TELEGRAM_WEBHOOK_SECRET` é registrado no Telegram pelo `/setproduction` e
validado em cada update; sem ele configurado a validação é pulada (dev).

## Desenvolvimento

  * `mix setup` — dependências + banco
  * `./scripts/dev_up.sh` — sobe tudo: Postgres + RabbitMQ (docker), túnel ngrok,
    registra o webhook do Telegram no túnel e inicia o Phoenix.
    **Cuidado**: aponta o webhook do bot do token em `dev.secret.exs` para a sua
    máquina — se for o token de produção, produção para de receber updates.
  * Manual: `docker-compose up -d` + `mix phx.server` ([`localhost:4000`](http://localhost:4000))
  * `mix test` — a suíte não exige RabbitMQ nem AWS (broker e SSM desligados em `config/test.exs`)
