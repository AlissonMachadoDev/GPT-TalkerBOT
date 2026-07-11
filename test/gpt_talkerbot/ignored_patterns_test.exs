defmodule GptTalkerbot.IgnoredPatternsTest do
  use GptTalkerbot.DataCase

  alias GptTalkerbot.{IgnoredPatterns, Memory}
  alias GptTalkerbot.Memory.ConversationMessage

  @chat_id "-100888"

  # O banco é revertido a cada teste, mas o cache ETS não
  setup do
    IgnoredPatterns.reset_cache()
    :ok
  end

  describe "add/2 e ignored?/2" do
    test "mensagem contendo o padrão é ignorada, sem diferenciar caixa" do
      assert :ok = IgnoredPatterns.add(@chat_id, "Jogo do Bicho")

      assert IgnoredPatterns.ignored?(@chat_id, "alguém aí no JOGO DO BICHO hoje?")
      refute IgnoredPatterns.ignored?(@chat_id, "bom dia grupo")
    end

    test "padrão duplicado não é registrado duas vezes" do
      assert :ok = IgnoredPatterns.add(@chat_id, "spam")
      assert :already_exists = IgnoredPatterns.add(@chat_id, "  SPAM  ")
      assert IgnoredPatterns.list(@chat_id) == ["spam"]
    end

    test "padrão vazio é rejeitado" do
      assert {:error, :empty} = IgnoredPatterns.add(@chat_id, "   ")
    end

    test "padrões valem só para o próprio chat" do
      assert :ok = IgnoredPatterns.add(@chat_id, "segredo")

      refute IgnoredPatterns.ignored?("-100999", "meu segredo aqui")
    end

    test "texto não binário nunca é ignorado" do
      refute IgnoredPatterns.ignored?(@chat_id, nil)
    end
  end

  describe "integração com a memória de conversa" do
    test "exchange com mensagem ignorada não é salvo" do
      assert :ok = IgnoredPatterns.add(@chat_id, "bitcoin")

      assert {:ok, :ignored} =
               Memory.save_exchange(@chat_id, "111", "Beto: compra bitcoin agora", "não caio nessa")

      assert Repo.aggregate(ConversationMessage, :count) == 0
    end

    test "exchange normal continua sendo salvo" do
      assert :ok = IgnoredPatterns.add(@chat_id, "bitcoin")

      {:ok, _} = Memory.save_exchange(@chat_id, "111", "Beto: bom dia rato", "bom dia, plebe")

      assert Repo.aggregate(ConversationMessage, :count) == 2
    end
  end
end
