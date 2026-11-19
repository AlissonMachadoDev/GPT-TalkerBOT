# Diagnóstico da cena multi-voz na Fish Audio.
#
# Responde a uma pergunta só: quando o áudio sai com a mesma voz em todas as
# falas, a culpa é do nosso lado (busca de voz, montagem do corpo) ou do
# drama-3? Pra isso imprime o corpo exato que o código manda pro /v1/tts e um
# curl pronto usando as três vozes OFICIAIS do roster do drama-3 — se o áudio
# desse curl sair em voz única, o problema não é nosso.
#
# Não chama API nenhuma: só monta e imprime.
#
#   mix run scripts/diagnose_fish_dialogue.exs

alias GptTalkerbot.RuntimeEnvs
alias GptTalkerbotWeb.Services.TTS

# Roster público do drama-3 (docs.fish.audio/features/text-to-speech/drama-3).
# Vozes do próprio modelo, então descartam qualquer dúvida de compatibilidade
# entre voz clonada e cena multi-speaker.
roster = [
  {"Adrian", "bf322df2096a46f18c579d0baa36f41d"},
  {"Delia", "c70cfb98867a4bfb9ae20d2401257b92"},
  {"Sheila", "f3a2b90078d54a65af4b95f63bc7798e"}
]

linhas = [
  "Olha só quem apareceu no meu auditório.",
  "Ô loco meu, tu tá maluco?",
  "Para tudo! Essa eu não esperava."
]

cena =
  [roster, linhas]
  |> Enum.zip()
  |> Enum.map(fn {{_nome, id}, texto} -> %{text: texto, voice_id: id} end)

separador = String.duplicate("─", 72)

IO.puts("\n#{separador}\nCONFIGURAÇÃO EM VIGOR NESTE AMBIENTE")
IO.puts(separador)
IO.puts("tts_provider ....: #{inspect(RuntimeEnvs.get_tts_provider())}")
IO.puts("fish_model ......: #{inspect(RuntimeEnvs.get_fish_model())}")
IO.puts("fish_drama? .....: #{RuntimeEnvs.fish_drama?()}")
IO.puts("tts_dialogue? ...: #{RuntimeEnvs.tts_dialogue?()}")

IO.puts("""

ATENÇÃO: isso é a config LOCAL (dev.secret.exs + defaults). Em produção quem
manda é o SSM — confira por lá com /showvariables no chat.
""")

unless RuntimeEnvs.tts_dialogue?() do
  IO.puts("""
  >>> tts_dialogue? está FALSE: neste ambiente o pipeline nem separa as falas,
  >>> e todo áudio sairia em voz única. Em produção isso exige tts_provider=fish
  >>> com fish_model=drama-3 (ou tts_provider=elevenlabs).
  """)
end

IO.puts("#{separador}\nCASO 1 — três vozes distintas (o que DEVE acontecer)")
IO.puts(separador)
corpo_ok = TTS.build_fish_dialogue_body(cena)
IO.puts(Jason.encode!(corpo_ok, pretty: true))
IO.puts("\nvozes no reference_id: #{length(corpo_ok["reference_id"])}")

IO.puts("\n#{separador}\nCASO 2 — busca de voz falhou e tudo caiu na default")
IO.puts(separador)

IO.puts("""
Simula o cenário em que nenhum nome do elenco existe na biblioteca: todas as
falas recebem o mesmo voice_id. Repare que reference_id colapsa pra UMA entrada
e todo <|speaker:N|> vira speaker:0 — é esse corpo que produz monólogo, e ele
sai idêntico no drama-3 e em qualquer outro modelo.
""")

colapsada = Enum.map(cena, &%{&1 | voice_id: "MESMA_VOZ_DEFAULT"})
corpo_colapsado = TTS.build_fish_dialogue_body(colapsada)
IO.puts(Jason.encode!(corpo_colapsado, pretty: true))
IO.puts("\nvozes no reference_id: #{length(corpo_colapsado["reference_id"])}")

IO.puts("\n#{separador}\nCURL DE ISOLAMENTO — rode isso à mão")
IO.puts(separador)

curl = """
curl --fail --show-error --request POST https://api.fish.audio/v1/tts \\
  --header "Authorization: Bearer $FISH_API_KEY" \\
  --header "Content-Type: application/json" \\
  --header "model: drama-3" \\
  --data '#{Jason.encode!(%{corpo_ok | "format" => "mp3"})}' \\
  --output /tmp/cena_drama3.mp3
"""

IO.puts("""

Usa as três vozes do roster do drama-3, então não depende da nossa busca de voz
nem de voz clonada. Precisa do FISH_API_KEY no ambiente.

  export FISH_API_KEY=...

#{curl}
COMO LER O RESULTADO

  Três vozes diferentes no mp3
    -> o drama-3 e o nosso corpo estão certos. A voz única em produção vem da
       BUSCA DE VOZ: os nomes do elenco não existem na biblioteca e todos caem
       na default. Procure no log por "VoiceSearch: fish sem voz pra ..." e pelo
       aviso de monólogo em resolve_cast/1.

  Mesma voz nas três falas
    -> o corpo está conforme a doc e as vozes são as oficiais do modelo, então o
       problema é do drama-3, não nosso. Casa com o issue aberto
       github.com/fishaudio/fish-speech/issues/1358 (speaker 1 renderizado na voz
       do speaker 0), até agora só reproduzido em self-hosted e sem resposta de
       maintainer. Nesse caso o caminho é abrir ticket na Fish com esse mp3.

  Erro HTTP
    -> cole a resposta aqui; o /v1/tts costuma explicar qual campo recusou.
""")
