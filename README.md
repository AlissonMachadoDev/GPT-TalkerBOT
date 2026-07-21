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

Público (chats permitidos): `/humor`, `/fatos`, `/esquece`, `/resumo`,
`/voz <pedido>` (responde em nota de voz — ver [Áudio (TTS)](#áudio-tts)),
`/enquete <instrução>` (enquete gerada a partir da instrução),
`/enquete_random` (enquete maliciosa com membros do grupo como opções), `/sorte`
(dado/caça-níquel nativo), `/ratowarn` (warn debochado na mensagem respondida;
aos 6 warns o rato perdoa e zera), `/bangif` (bane da memória o GIF respondido).

O bot mantém um registro de membros por chat (construído por observação —
a Bot API não lista membros), mostra "digitando..." antes de responder,
memoriza GIFs postados e reposta um aleatório de vez em quando, e pode
mencionar membros com notificação via `tg://user?id=`.

Admin (apenas owner): `/setproduction`, `/updatevariables`, `/setgrok`, `/setopenai`,
`/cleardatabase` (apaga toda a memória do bot — conversas, fatos, contextos e humores;
tabelas legadas de registro ficam intactas).

Legado: `/register`, `/register_group`.

## Configuração

Env vars (prod): `DATABASE_URL`, `SECRET_KEY_BASE`, `OPENAI_API_KEY`,
`GROK_API_KEY`, `ELEVENLABS_API_KEY`, `TELEGRAM_API_KEY`, `SERVER_HOST`,
`TELEGRAM_WEBHOOK_SECRET`, `RABBITMQ_HOST`, `RABBITMQ_USERNAME`,
`RABBITMQ_PASSWORD`, credenciais AWS.

Parâmetros no SSM (path `/gpt_talkerbot/prod/`), atualizáveis sem deploy via
`/updatevariables`: `default_prompt`, `owner_id`, `allowed_users`,
`allowed_groups`, `user_labels`, `spice_threshold`, `temperature`,
`grok_reasoning`, `openai_model`, `grok_model`, `relevance_threshold`,
`always_include_last`, `max_context_messages`, `session_gap_minutes`,
`mood_duration`, `interject_probability`, `interject_cooldown_minutes`,
`reaction_probability`, `gif_probability`, `daily_summary_hour` (fora de 0–23
desativa), `utc_offset`, `tts_provider`, `elevenlabs_voices`,
`elevenlabs_model` (ver [Áudio (TTS)](#áudio-tts)).

Acesso é *fail closed*: com `allowed_users` e `allowed_groups` vazios o bot
não responde a ninguém.

`TELEGRAM_WEBHOOK_SECRET` é registrado no Telegram pelo `/setproduction` e
validado em cada update; sem ele configurado a validação é pulada (dev).

## Áudio (TTS)

O bot responde em nota de voz de dois jeitos: pelo comando `/voz <pedido>` (o
texto é gerado por IA in-character e então sintetizado) ou quando o modelo
termina uma resposta com o marcador `[[ratobo:audio]]` (acionado por pedidos
naturais de áudio no chat). A síntese fica em `Services.TTS`.

**Provider** — `tts_provider` no SSM: `openai` (padrão) ou `elevenlabs`. Sem
`ELEVENLABS_API_KEY` ou sem a voz `default` configurada, o TTS cai pro OpenAI
automaticamente.

**Adicionar uma voz (ElevenLabs)** — as vozes ficam no parâmetro SSM
`elevenlabs_voices`, no formato `nome:voice_id;nome:voice_id` (mesmo formato do
`user_labels`). O `voice_id` vem do painel da ElevenLabs (Voices). A voz `default`
é obrigatória; as demais são para uso por contexto no futuro:

```
default:21m00Tcm4TlvDq8ikWAM;male_1:pNInz6obpgDQGcFmaJgB;narrador:...
```

Hoje **só a `default` é usada** — toda nota de voz sai com ela. A seleção de voz
por contexto/diálogo ainda não é dirigida pelo prompt; existe apenas o gancho de
código `RuntimeEnvs.get_elevenlabs_voice("nome")`, a ser ligado quando os
diálogos multi-voz forem implementados.

## Desenvolvimento

  * `mix setup` — dependências + banco
  * `./scripts/dev_up.sh` — sobe tudo: Postgres + RabbitMQ (docker), túnel ngrok,
    registra o webhook do Telegram no túnel e inicia o Phoenix.
    **Cuidado**: aponta o webhook do bot do token em `dev.secret.exs` para a sua
    máquina — se for o token de produção, produção para de receber updates.
  * Manual: `docker-compose up -d` + `mix phx.server` ([`localhost:4000`](http://localhost:4000))
  * `mix test` — a suíte não exige RabbitMQ nem AWS (broker e SSM desligados em `config/test.exs`)
