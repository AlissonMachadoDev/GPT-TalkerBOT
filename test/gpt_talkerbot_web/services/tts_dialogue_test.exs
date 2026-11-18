defmodule GptTalkerbotWeb.Services.TTSDialogueTest do
  # async: false porque os testes de capacidade mexem no persistent_term do
  # RuntimeEnvs, que é global ao nó
  use ExUnit.Case, async: false

  alias GptTalkerbot.PostActions
  alias GptTalkerbot.RuntimeEnvs
  alias GptTalkerbotWeb.Services.TTS

  defp put_env(overrides) do
    previous = :persistent_term.get(RuntimeEnvs, %{})
    :persistent_term.put(RuntimeEnvs, Map.merge(previous, overrides))
    on_exit(fn -> :persistent_term.put(RuntimeEnvs, previous) end)
  end

  describe "build_fish_dialogue_body/1" do
    test "cada fala é prefixada pelo marcador da posição da voz" do
      body =
        TTS.build_fish_dialogue_body([
          %{text: "Oi.", voice_id: "voz_a"},
          %{text: "Tchau.", voice_id: "voz_b"}
        ])

      assert body["text"] == "<|speaker:0|>Oi.<|speaker:1|>Tchau."
      assert body["reference_id"] == ["voz_a", "voz_b"]
    end

    test "personagem que volta a falar reusa o índice, sem duplicar no reference_id" do
      body =
        TTS.build_fish_dialogue_body([
          %{text: "Eu começo.", voice_id: "voz_a"},
          %{text: "Eu respondo.", voice_id: "voz_b"},
          %{text: "Eu encerro.", voice_id: "voz_a"}
        ])

      assert body["text"] ==
               "<|speaker:0|>Eu começo.<|speaker:1|>Eu respondo.<|speaker:0|>Eu encerro."

      assert body["reference_id"] == ["voz_a", "voz_b"]
    end

    test "uma fala só ainda sai com marcador, pro modelo não ler o texto como narração" do
      body = TTS.build_fish_dialogue_body([%{text: "Sozinho.", voice_id: "voz_a"}])

      assert body["text"] == "<|speaker:0|>Sozinho."
      assert body["reference_id"] == ["voz_a"]
    end

    test "o formato é o opus que o sendVoice do Telegram espera" do
      body = TTS.build_fish_dialogue_body([%{text: "x", voice_id: "v"}])

      assert body["format"] == "opus"
    end

    test "direção e tag prosódica sobrevivem intactas dentro da fala" do
      body =
        TTS.build_fish_dialogue_body([
          %{text: "[quase rindo] <emphasis>agora</emphasis> não.", voice_id: "v"}
        ])

      assert body["text"] == "<|speaker:0|>[quase rindo] <emphasis>agora</emphasis> não."
    end
  end

  describe "synthesize_dialogue/1 — guardas antes de qualquer chamada HTTP" do
    test "recusa quando o provider não monta diálogo multi-voz" do
      put_env(%{tts_provider: "openai"})

      assert TTS.synthesize_dialogue([
               %{text: "a", voice_id: "v1"},
               %{text: "b", voice_id: "v2"}
             ]) == {:error, :unsupported}
    end

    test "recusa a Fish fora do drama-3, que leria os marcadores como texto" do
      put_env(%{tts_provider: "fish", fish_model: "s2.1-pro", fish_api_key: "chave"})

      assert TTS.synthesize_dialogue([
               %{text: "a", voice_id: "v1"},
               %{text: "b", voice_id: "v2"}
             ]) == {:error, :unsupported}
    end

    test "recusa fala sem voz resolvida em vez de montar reference_id furado" do
      put_env(%{tts_provider: "fish", fish_model: "drama-3", fish_api_key: "chave"})

      assert TTS.synthesize_dialogue([
               %{text: "a", voice_id: "v1"},
               %{text: "b", voice_id: ""}
             ]) == {:error, :no_voice}
    end

    test "sem api_key a Fish no drama-3 para antes de chamar a API" do
      put_env(%{tts_provider: "fish", fish_model: "drama-3", fish_api_key: ""})

      assert TTS.synthesize_dialogue([
               %{text: "a", voice_id: "v1"},
               %{text: "b", voice_id: "v2"}
             ]) == {:error, :no_api_key}
    end

    test "sem api_key a ElevenLabs para antes de chamar a API" do
      put_env(%{tts_provider: "elevenlabs", elevenlabs_api_key: ""})

      assert TTS.synthesize_dialogue([
               %{text: "a", voice_id: "v1"},
               %{text: "b", voice_id: "v2"}
             ]) == {:error, :no_api_key}
    end

    test "lista vazia não casa com a cláusula" do
      assert_raise FunctionClauseError, fn -> TTS.synthesize_dialogue([]) end
    end
  end

  describe "RuntimeEnvs.tts_dialogue?/0 e fish_drama?/0" do
    test "elevenlabs monta diálogo independente do fish_model" do
      put_env(%{tts_provider: "elevenlabs", fish_model: "s2.1-pro"})

      assert RuntimeEnvs.tts_dialogue?()
      refute RuntimeEnvs.fish_drama?()
    end

    test "fish no drama-3 monta diálogo" do
      put_env(%{tts_provider: "fish", fish_model: "drama-3"})

      assert RuntimeEnvs.tts_dialogue?()
      assert RuntimeEnvs.fish_drama?()
    end

    test "fish fora do drama-3 não monta" do
      put_env(%{tts_provider: "fish", fish_model: "s2.1-pro"})

      refute RuntimeEnvs.tts_dialogue?()
      refute RuntimeEnvs.fish_drama?()
    end

    test "fish_model em drama-3 não vale nada com outro provider ativo" do
      put_env(%{tts_provider: "openai", fish_model: "drama-3"})

      refute RuntimeEnvs.tts_dialogue?()
      refute RuntimeEnvs.fish_drama?()
    end
  end

  describe "PostActions.instruction/0 acompanha o provider" do
    test "no drama-3 pede direção em português e oferece tag prosódica" do
      put_env(%{tts_provider: "fish", fish_model: "drama-3"})
      instruction = PostActions.instruction()

      assert instruction =~ "[quase rindo]"
      assert instruction =~ "<emphasis>"
      refute instruction =~ "[mischievously]"
    end

    test "fora do drama-3 mantém o vocabulário curto de audio tag" do
      put_env(%{tts_provider: "elevenlabs", fish_model: "drama-3"})
      instruction = PostActions.instruction()

      assert instruction =~ "[mischievously]"
      refute instruction =~ "<emphasis>"
    end

    test "avisa que o diálogo sai em voz única quando o provider não suporta" do
      put_env(%{tts_provider: "fish", fish_model: "s2.1-pro"})

      assert PostActions.instruction() =~ "não monta diálogo multi-voz"
    end

    test "não avisa nada disso quando o provider suporta" do
      put_env(%{tts_provider: "fish", fish_model: "drama-3"})

      refute PostActions.instruction() =~ "não monta diálogo multi-voz"
    end

    test "as partes fixas (gif, marcador de voz) aparecem em qualquer provider" do
      put_env(%{tts_provider: "openai"})
      instruction = PostActions.instruction()

      assert instruction =~ "[[ratobo:gif]]"
      assert instruction =~ "[[ratobo:audio]]"
      assert instruction =~ "[[ratobo:voice:nome:"
    end
  end
end
