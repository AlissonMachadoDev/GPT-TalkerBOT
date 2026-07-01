defmodule GptTalkerbot.Telegram.ContentDescriberTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Telegram.ContentDescriber

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
    poll = %{"question" => "Melhor pizza?", "options" => [%{"text" => "Calabresa"}, %{"text" => "Quatro queijos"}]}

    assert ContentDescriber.describe(%{"poll" => poll}) =~ "0 votos"
  end

  test "sticker com e sem emoji" do
    assert ContentDescriber.describe(%{"sticker" => %{"emoji" => "😂"}}) == "[sticker 😂]"
    assert ContentDescriber.describe(%{"sticker" => %{}}) == "[sticker]"
  end

  test "dado com valor" do
    assert ContentDescriber.describe(%{"dice" => %{"emoji" => "🎲", "value" => 6}}) == "[🎲: caiu 6]"
  end

  test "áudio com duração" do
    assert ContentDescriber.describe(%{"voice" => %{"duration" => 32}}) == "[áudio de 32s]"
  end

  test "mídia com legenda concatena a legenda" do
    assert ContentDescriber.describe(%{"photo" => [%{}], "caption" => "olha isso"}) == "[foto] olha isso"
  end

  test "GIF vence document (retrocompatibilidade da API)" do
    assert ContentDescriber.describe(%{"animation" => %{}, "document" => %{"file_name" => "x.mp4"}}) == "[GIF]"
  end

  test "documento usa o nome do arquivo" do
    assert ContentDescriber.describe(%{"document" => %{"file_name" => "notas.pdf"}}) == "[arquivo notas.pdf]"
  end

  test "conteúdo desconhecido retorna nil" do
    assert ContentDescriber.describe(%{"algo_novo" => %{}}) == nil
    assert ContentDescriber.describe(nil) == nil
  end
end
