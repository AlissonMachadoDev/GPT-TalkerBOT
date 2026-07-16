defmodule GptTalkerbot.Telegram.ContentDescriberTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Telegram.ContentDescriber
  alias GptTalkerbot.Telegram.Message

  test "texto passa direto" do
    assert ContentDescriber.describe(%{"text" => "oi ratobô"}) == "oi ratobô"
  end

  test "enquete vira descrição com pergunta, opções e votos" do
    poll = %{
      "question" => "Quem é mais provável de sumir?",
      "options" => [%{"text" => "Ana"}, %{"text" => "Beto"}],
      "total_voter_count" => 14
    }

    assert ContentDescriber.describe(%{"poll" => poll}) ==
             ~s([enquete: "Quem é mais provável de sumir?" — opções: Ana, Beto | 14 votos])
  end

  test "enquete sem votos ainda descreve" do
    poll = %{
      "question" => "Melhor pizza?",
      "options" => [%{"text" => "Calabresa"}, %{"text" => "Quatro queijos"}]
    }

    assert ContentDescriber.describe(%{"poll" => poll}) =~ "0 votos"
  end

  test "sticker com e sem emoji" do
    assert ContentDescriber.describe(%{"sticker" => %{"emoji" => "😂"}}) == "[sticker 😂]"
    assert ContentDescriber.describe(%{"sticker" => %{}}) == "[sticker]"
  end

  test "dado com valor" do
    assert ContentDescriber.describe(%{"dice" => %{"emoji" => "🎲", "value" => 6}}) ==
             "[🎲: caiu 6]"
  end

  test "áudio com duração" do
    assert ContentDescriber.describe(%{"voice" => %{"duration" => 32}}) == "[áudio de 32s]"
  end

  test "mídia com legenda concatena a legenda" do
    assert ContentDescriber.describe(%{"photo" => [%{}], "caption" => "olha isso"}) ==
             "[foto] olha isso"
  end

  test "GIF vence document (retrocompatibilidade da API)" do
    assert ContentDescriber.describe(%{
             "animation" => %{},
             "document" => %{"file_name" => "x.mp4"}
           }) == "[GIF]"
  end

  test "rich message com tabela vira texto legível" do
    rich_message = %{
      "blocks" => [
        %{"type" => "paragraph", "text" => "Olha a classificação"},
        %{
          "type" => "table",
          "caption" => "Cuzinho",
          "cells" => [
            [%{"text" => "Bom"}, %{"text" => "Ruim"}],
            [%{"text" => "Melecadinho"}, %{"text" => "Sujo"}]
          ]
        }
      ]
    }

    assert ContentDescriber.describe(%{"rich_message" => rich_message}) ==
             "Olha a classificação\nCuzinho\nBom | Ruim\nMelecadinho | Sujo"
  end

  test "rich message vazia continua sem descrição" do
    assert ContentDescriber.describe(%{"rich_message" => %{"blocks" => []}}) == nil
  end

  test "tabela da mensagem respondida entra no texto usado pelo handler" do
    params = %{
      "text" => "comenta essa tabela",
      "chat" => %{"id" => -100, "type" => "supergroup"},
      "from" => %{"id" => 1, "first_name" => "Frankie"},
      "reply_to_message" => %{
        "message_id" => 9,
        "chat" => %{"id" => -100, "type" => "supergroup"},
        "from" => %{"id" => 1, "first_name" => "Frankie"},
        "rich_message" => %{
          "blocks" => [
            %{
              "type" => "table",
              "caption" => "Notas",
              "cells" => [[%{"text" => "Bom"}, %{"text" => "Ruim"}]]
            }
          ]
        }
      }
    }

    message =
      params
      |> Message.cast()
      |> Ecto.Changeset.apply_changes()

    assert message.reply_to_message.text == "Notas\nBom | Ruim"
  end

  test "documento usa o nome do arquivo" do
    assert ContentDescriber.describe(%{"document" => %{"file_name" => "notas.pdf"}}) ==
             "[arquivo notas.pdf]"
  end

  test "conteúdo desconhecido retorna nil" do
    assert ContentDescriber.describe(%{"algo_novo" => %{}}) == nil
    assert ContentDescriber.describe(nil) == nil
  end
end
