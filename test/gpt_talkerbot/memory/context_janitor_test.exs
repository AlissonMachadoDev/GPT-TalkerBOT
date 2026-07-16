defmodule GptTalkerbot.Memory.ContextJanitorTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Memory.ContextJanitor

  describe "review_list/1" do
    test "numera a partir de 1 com o role e achata quebras de linha" do
      messages = [
        %{role: "user", content: "oi\ntudo bem?"},
        %{role: "assistant", content: "na paz"}
      ]

      assert ContextJanitor.review_list(messages) ==
               "1. [user] oi tudo bem?\n2. [assistant] na paz"
    end

    test "trunca conteúdo longo para não estourar o prompt de revisão" do
      [line] =
        ContextJanitor.review_list([%{role: "user", content: String.duplicate("a", 500)}])
        |> String.split("\n")

      assert String.length(line) < 350
    end
  end

  describe "parse_verdict/2" do
    test "aceita o JSON esperado" do
      assert ContextJanitor.parse_verdict(~s({"lixo": [2, 5]}), 10) == {:ok, [2, 5]}
    end

    test "aceita veredito limpo" do
      assert ContextJanitor.parse_verdict(~s({"lixo": []}), 10) == {:ok, []}
    end

    test "remove cercas de código que o modelo às vezes adiciona" do
      assert ContextJanitor.parse_verdict("```json\n{\"lixo\": [1]}\n```", 3) == {:ok, [1]}
    end

    test "descarta posições fora do intervalo revisado e não-inteiros" do
      assert ContextJanitor.parse_verdict(~s({"lixo": [0, 2, 99, "3", 2]}), 5) == {:ok, [2]}
    end

    test "resposta que não é o JSON combinado vira erro, nunca deleção" do
      assert ContextJanitor.parse_verdict("apago tudo então?", 5) == {:error, :invalid_verdict}

      assert ContextJanitor.parse_verdict(~s({"outra_chave": [1]}), 5) ==
               {:error, :invalid_verdict}
    end
  end
end
