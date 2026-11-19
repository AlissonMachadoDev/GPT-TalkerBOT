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
`GROK_API_KEY`, `ELEVENLABS_API_KEY`, `FISH_API_KEY`, `TELEGRAM_API_KEY`,
`SERVER_HOST`, `TELEGRAM_WEBHOOK_SECRET`, `RABBITMQ_HOST`, `RABBITMQ_USERNAME`,
`RABBITMQ_PASSWORD`, credenciais AWS.

Parâmetros no SSM (path `/gpt_talkerbot/prod/`), atualizáveis sem deploy via
`/updatevariables`: `default_prompt`, `owner_id`, `allowed_users`,
`allowed_groups`, `user_labels`, `spice_threshold`, `temperature`,
`grok_reasoning`, `openai_model`, `grok_model`, `relevance_threshold`,
`always_include_last`, `max_context_messages`, `session_gap_minutes`,
`mood_duration`, `interject_probability`, `interject_cooldown_minutes`,
`reaction_probability`, `gif_probability`, `daily_summary_hour` (fora de 0–23
desativa), `utc_offset`, `tts_provider`, `elevenlabs_voices`,
`elevenlabs_model`, `fish_voices`, `fish_model` (ver [Áudio (TTS)](#áudio-tts)).

Acesso é *fail closed*: com `allowed_users` e `allowed_groups` vazios o bot
não responde a ninguém.

`TELEGRAM_WEBHOOK_SECRET` é registrado no Telegram pelo `/setproduction` e
validado em cada update; sem ele configurado a validação é pulada (dev).

## Áudio (TTS)

O bot responde em nota de voz de dois jeitos: pelo comando `/voz <pedido>` (o
texto é gerado por IA in-character e então sintetizado) ou quando o modelo
termina uma resposta com o marcador `[[ratobo:audio]]` (acionado por pedidos
naturais de áudio no chat). A síntese fica em `Services.TTS`.

**Provider** — `tts_provider` no SSM: `openai` (padrão), `elevenlabs` ou `fish`.
Sem a respectiva `*_API_KEY` ou sem a voz `default` configurada, o TTS cai pro
OpenAI automaticamente.

**Adicionar uma voz (ElevenLabs)** — as vozes ficam no parâmetro SSM
`elevenlabs_voices`, no formato `nome:voice_id;nome:voice_id` (mesmo formato do
`user_labels`). O `voice_id` vem do painel da ElevenLabs (Voices). A voz `default`
é obrigatória; as demais são para uso por contexto no futuro:

```
default:21m00Tcm4TlvDq8ikWAM;male_1:pNInz6obpgDQGcFmaJgB;narrador:...
```

**Adicionar uma voz (Fish Audio)** — mesmo esquema no parâmetro SSM
`fish_voices`: `nome:reference_id;nome:reference_id`. O `reference_id` vem da
Voice Library da Fish Audio. A voz `default` cobre o que a busca dinâmica não
achar.

**Modelo da Fish** — `fish_model` no SSM, padrão `drama-3`. É o único que
entende direção de atuação em frase inteira e em português
(`[sussurrando, fingindo pena]`), tags prosódicas (`<whisper>`, `<emphasis>`,
`<soft>`, `<fast>`, `<slow>`, `<stress>`, `<forceful>`) e várias vozes num áudio
só — **sem ele o modo bipolar não existe** e toda cena sai em voz única.

Custa US$ 50 por milhão de bytes UTF-8 contra US$ 15 do `s2.1-pro`. Se o custo
apertar, o SSM derruba pra lá e o pipeline se adapta sozinho:
`RuntimeEnvs.fish_drama?/0` e `tts_dialogue?/0` param de separar as falas e a
instrução mandada ao LLM deixa de ensinar o modo bipolar. Valor inválido não
quebra a chamada — a Fish cai em `s2.1-pro` silenciosamente, então um typo aqui
se manifesta como cena em voz única, não como erro.

**Voz por contexto** — o modelo pode pedir uma voz específica com
`[[ratobo:voice:nome:...]]` (busca por nome na biblioteca do provider) ou
`[[ratobo:voice:estilo:...]]` (vocabulário fixo → `tag`/`gender`/`age`), em
`Services.VoiceSearch`. Busca sem resultado cai na voz `default` do provider
ativo, sem derrubar a síntese.

**Diálogo multi-voz** — várias vozes num áudio só, sempre dentro do modo
bipolar (ver abaixo). Funciona na ElevenLabs (`text-to-dialogue`, até 10 vozes)
e na Fish com `drama-3` (`reference_id` em array + marcadores `<|speaker:N|>`).
Nos demais o pipeline nem separa as falas: o áudio sai inteiro na voz da
primeira — e a instrução mandada ao LLM diz isso, pra ele não contar com o que
não existe.

**Modo bipolar** — o jeito curto de montar uma cena. É um **comando explícito**:
só acionado quando a mensagem contém as palavras "modo bipolar"
(`PostActions.bipolar_requested?/1`). Citar duas pessoas, pedir uma discussão ou
descrever uma cena não aciona — aí a resposta sai como áudio de voz única.

A trava é no pipeline, não só no prompt: sem a expressão escrita, nenhuma
resposta vira cena, por mais que o modelo declare elenco ou repita marcador de
voz por fala. Isso evita que o bot gaste o endpoint de diálogo (e as buscas de
voz) sempre que alguém mencionar dois nomes.

Pedido o modo, o modelo declara o elenco uma vez e escreve as falas como
roteiro:

```
[[ratobo:bipolar:Silvio Santos, Faustão]]
Silvio Santos: Olha só quem apareceu no meu auditório.
Faustão: Ô loco meu, tu tá maluco?
Silvio Santos: Para tudo!
```

Elenco de até 4 nomes. Cada personagem é buscado **uma vez**, não uma vez por
fala — como a busca por nome gasta até duas requisições, uma cena de seis falas
entre dois personagens passa de 12 requests para 4. `Nome:` só é lido como fala
quando o marcador de elenco existe e o nome bate com alguém dele (aceitando
primeiro nome e ignorando acento/caixa), então frase comum terminada em
dois-pontos continua sendo texto. Linha sem nome pertence à fala anterior, e
narração antes da primeira fala é descartada.

O separador aceita vírgula e a conjunção "e", porque é assim que se escreve
lista em português e o modelo espelha o pedido do usuário: `A, B e C` e
`A, B, e C` dão o mesmo elenco de três. Quando o separador faz parte do nome,
**parênteses escapam**:

```
[[ratobo:bipolar:(Chico e Felipe), Galvão]]
```

São dois personagens, o primeiro chamado "Chico e Felipe" — uma busca, não
duas. Vale para vírgula também (`(Tom, Jerry)`). Na fala os parênteses são
opcionais: tanto `Chico e Felipe:` quanto `(Chico e Felipe):` casam.

O fallback de texto é o próprio roteiro, que já se lê sozinho — se o TTS cair,
a cena vira mensagem normal com cada fala atribuída.

**Teto de tamanho da cena** — a ElevenLabs documenta no máximo 2.000 caracteres
somando todos os `inputs[].text` do `text-to-dialogue`; acima disso a resposta
pode truncar ou dar erro de validação. A Fish não publica teto no `/v1/tts`, mas
cobra por byte UTF-8, então lá o corte é de custo (4.000). Em ambos o corte é
por fala inteira: `TTS.trim_to_budget/2` descarta falas do fim até caber, em vez
de deixar alguém mudo no meio da frase.

## Desenvolvimento

  * `mix setup` — dependências + banco
  * `./scripts/dev_up.sh` — sobe tudo: Postgres + RabbitMQ (docker), túnel ngrok,
    registra o webhook do Telegram no túnel e inicia o Phoenix.
    **Cuidado**: aponta o webhook do bot do token em `dev.secret.exs` para a sua
    máquina — se for o token de produção, produção para de receber updates.
  * Manual: `docker-compose up -d` + `mix phx.server` ([`localhost:4000`](http://localhost:4000))
  * `mix test` — a suíte não exige RabbitMQ nem AWS (broker e SSM desligados em `config/test.exs`)
