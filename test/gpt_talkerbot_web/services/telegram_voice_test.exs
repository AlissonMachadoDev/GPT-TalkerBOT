defmodule GptTalkerbotWeb.Services.TelegramVoiceTest do
  use ExUnit.Case, async: true

  alias GptTalkerbotWeb.Services.Telegram

  defp field(%Tesla.Multipart{parts: parts}, name) do
    Enum.find(parts, fn part -> part.dispositions[:name] == name end)
  end

  describe "build_voice_multipart/1" do
    test "monta o áudio como parte de arquivo 'voice' em ogg" do
      mp = Telegram.build_voice_multipart(%{chat_id: 123, voice: "OGG_BYTES"})

      voice = field(mp, "voice")
      assert voice.body == "OGG_BYTES"
      assert voice.dispositions[:filename] == "voz.ogg"
      assert {"content-type", "audio/ogg"} in voice.headers
    end

    test "chat_id vira campo de texto" do
      mp = Telegram.build_voice_multipart(%{chat_id: 123, voice: "x"})

      assert field(mp, "chat_id").body == "123"
    end

    test "caption e reply_to_message_id são opcionais e omitidos quando nil" do
      mp = Telegram.build_voice_multipart(%{chat_id: 1, voice: "x"})

      assert field(mp, "caption") == nil
      assert field(mp, "reply_to_message_id") == nil
    end

    test "caption e reply_to_message_id entram como campos quando fornecidos" do
      mp =
        Telegram.build_voice_multipart(%{
          chat_id: 1,
          voice: "x",
          caption: "legenda",
          reply_to_message_id: 42
        })

      assert field(mp, "caption").body == "legenda"
      assert field(mp, "reply_to_message_id").body == "42"
    end
  end
end
