defmodule GptTalkerbot.RuntimeEnvsTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.RuntimeEnvs

  describe "parse_user_labels/1" do
    test "faz parse de pares id:label separados por ponto-e-vírgula" do
      assert RuntimeEnvs.parse_user_labels("123:o brabo;456:estagiário") == %{
               "123" => "o brabo",
               "456" => "estagiário"
             }
    end

    test "remove aspas e espaços das labels" do
      assert RuntimeEnvs.parse_user_labels(~s(123: "o brabo" )) == %{"123" => "o brabo"}
    end

    test "label com dois-pontos no valor é preservada" do
      assert RuntimeEnvs.parse_user_labels("123:rei do 2:1") == %{"123" => "rei do 2:1"}
    end

    test "ignora pares malformados" do
      assert RuntimeEnvs.parse_user_labels("sem-separador;123:ok") == %{"123" => "ok"}
    end

    test "string vazia vira mapa vazio" do
      assert RuntimeEnvs.parse_user_labels("") == %{}
    end
  end

  describe "normalize_tts_provider/1" do
    test "reconhece elevenlabs como string e como átomo" do
      assert RuntimeEnvs.normalize_tts_provider("elevenlabs") == :elevenlabs
      assert RuntimeEnvs.normalize_tts_provider(:elevenlabs) == :elevenlabs
    end

    test "openai é o padrão para valor conhecido, desconhecido ou vazio" do
      assert RuntimeEnvs.normalize_tts_provider("openai") == :openai
      assert RuntimeEnvs.normalize_tts_provider(:openai) == :openai
      assert RuntimeEnvs.normalize_tts_provider("qualquer") == :openai
      assert RuntimeEnvs.normalize_tts_provider("") == :openai
    end
  end

  describe "normalize_voices/1" do
    test "faz parse da string do SSM no formato nome:voice_id" do
      assert RuntimeEnvs.normalize_voices("default:vDEF;male_1:vM1") == %{
               "default" => "vDEF",
               "male_1" => "vM1"
             }
    end

    test "mapa passa direto e valor inesperado vira mapa vazio" do
      assert RuntimeEnvs.normalize_voices(%{"default" => "v"}) == %{"default" => "v"}
      assert RuntimeEnvs.normalize_voices("") == %{}
      assert RuntimeEnvs.normalize_voices(nil) == %{}
    end
  end

  describe "resolve_voice/2" do
    @voices %{"default" => "vDEF", "male_1" => "vM1"}

    test "acha a voz pelo nome do contexto" do
      assert RuntimeEnvs.resolve_voice(@voices, "male_1") == "vM1"
    end

    test "cai na default quando o nome não existe" do
      assert RuntimeEnvs.resolve_voice(@voices, "narrador") == "vDEF"
    end

    test "sem default e sem match retorna vazio" do
      assert RuntimeEnvs.resolve_voice(%{"male_1" => "vM1"}, "narrador") == ""
      assert RuntimeEnvs.resolve_voice(%{}, "default") == ""
    end
  end

  describe "dump/0 e format_dump/0" do
    test "mascara todos os segredos" do
      dump = RuntimeEnvs.dump()

      for key <- [:openai_api_key, :grok_api_key, :elevenlabs_api_key, :telegram_webhook_secret] do
        assert dump[key] =~ ~r/^\(vazia\)$|^definida \(\d+ chars\)$/
      end
    end

    test "resume o prompt em tamanho em vez de despejar o conteúdo" do
      assert RuntimeEnvs.dump()[:default_prompt] =~ ~r/^\(vazio\)$|^\(\d+ chars\)$/
    end

    test "formata uma variável por linha" do
      formatted = RuntimeEnvs.format_dump()

      assert formatted =~ ~r/^temperature: /m
      assert formatted =~ ~r/^grok_model: /m
    end
  end
end
