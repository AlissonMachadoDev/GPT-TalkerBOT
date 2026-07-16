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

  describe "production_webhook_path/2" do
    test "inclui o secret token no webhook de produção" do
      assert {:ok, path} =
               Telegram.production_webhook_path("https://bot.example", "segredo_local")

      query = path |> String.split("?", parts: 2) |> List.last() |> URI.decode_query()

      assert query == %{
               "drop_pending_updates" => "true",
               "secret_token" => "segredo_local",
               "url" => "https://bot.example/webhook"
             }
    end

    test "omite o parâmetro quando o secret não está configurado" do
      assert {:ok, path} = Telegram.production_webhook_path("https://bot.example", "")

      query = path |> String.split("?", parts: 2) |> List.last() |> URI.decode_query()

      assert query == %{
               "drop_pending_updates" => "true",
               "url" => "https://bot.example/webhook"
             }
    end

    test "recusa alterar o webhook quando o host não está configurado" do
      assert Telegram.production_webhook_path("", "segredo_local") ==
               {:error, :server_host_not_configured}

      assert Telegram.production_webhook_path("   ", "segredo_local") ==
               {:error, :server_host_not_configured}
    end

    test "não duplica a barra final do host" do
      assert {:ok, path} =
               Telegram.production_webhook_path("https://bot.example/", "segredo_local")

      query = path |> String.split("?", parts: 2) |> List.last() |> URI.decode_query()
      assert query["url"] == "https://bot.example/webhook"
    end

    test "não duplica /webhook quando server_host já contém o caminho" do
      assert {:ok, path} =
               Telegram.production_webhook_path(
                 "https://gpt-talkerbot.alissonmachado.dev/webhook",
                 "segredo_local"
               )

      query = path |> String.split("?", parts: 2) |> List.last() |> URI.decode_query()
      assert query["url"] == "https://gpt-talkerbot.alissonmachado.dev/webhook"
      assert query["secret_token"] == "segredo_local"
    end
  end
end
