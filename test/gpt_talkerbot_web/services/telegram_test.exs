defmodule GptTalkerbotWeb.Services.TelegramTest do
  use ExUnit.Case, async: true

  alias GptTalkerbotWeb.Services.Telegram

  describe "poll_option/1" do
    test "string vira InputPollOption simples" do
      assert Telegram.poll_option("Fulano") == %{text: "Fulano"}
    end

    test "mapa com mídia passa intacto" do
      option = %{text: "Fulano", media: %{type: "photo", media: "file123"}}

      assert Telegram.poll_option(option) == option
    end
  end
end
