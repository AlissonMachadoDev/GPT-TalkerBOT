defmodule GptTalkerbot.Memory.ContextFilterTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Memory.ContextFilter

  # Embeddings sintéticos: [1.0, 0.0] é "sobre o mesmo assunto" da mensagem
  # atual, [0.0, 1.0] é assunto ortogonal (similaridade 0)
  @relevant [1.0, 0.0]
  @irrelevant [0.0, 1.0]

  defp user(content), do: %{role: "user", content: content, inserted_at: nil}
  defp assistant(content), do: %{role: "assistant", content: content, inserted_at: nil}

  test "lista vazia passa direto" do
    assert ContextFilter.filter([], "oi") == []
  end

  test "poucas mensagens não passam pelo filtro e perdem o timestamp" do
    messages = [user("a"), user("b")]

    assert ContextFilter.filter(messages, "oi") == [
             %{role: "user", content: "a"},
             %{role: "user", content: "b"}
           ]
  end

  test "descarta mensagem antiga irrelevante e mantém a relevante" do
    messages = [user("fora do assunto"), user("no assunto"), user("1"), user("2"), user("3"), user("4")]
    embeddings = [@irrelevant, @relevant, @relevant, @relevant, @relevant, @relevant, @relevant]

    result = ContextFilter.apply_relevance_filter(messages, embeddings)

    contents = Enum.map(result, & &1.content)
    refute "fora do assunto" in contents
    assert "no assunto" in contents
  end

  test "as últimas mensagens entram mesmo sem relevância" do
    messages = [user("velha"), user("a"), user("b"), user("c"), user("d")]
    # tudo irrelevante; as 4 últimas entram forçadas
    embeddings = List.duplicate(@irrelevant, 5) ++ [@relevant]

    result = ContextFilter.apply_relevance_filter(messages, embeddings)

    assert Enum.map(result, & &1.content) == ["a", "b", "c", "d"]
  end

  test "resposta do assistant acompanha a mensagem que a originou" do
    messages = [user("no assunto"), assistant("resposta"), user("1"), user("2"), user("3"), user("4")]
    # o embedding da resposta é irrelevante, mas ela segue a mensagem incluída
    embeddings = [@relevant, @irrelevant, @relevant, @relevant, @relevant, @relevant, @relevant]

    result = ContextFilter.apply_relevance_filter(messages, embeddings)

    assert %{role: "assistant", content: "resposta"} in result
  end

  test "resposta do assistant cai junto com a mensagem descartada" do
    messages = [user("fora"), assistant("resposta"), user("1"), user("2"), user("3"), user("4")]
    embeddings = [@irrelevant, @relevant, @relevant, @relevant, @relevant, @relevant, @relevant]

    result = ContextFilter.apply_relevance_filter(messages, embeddings)

    refute %{role: "assistant", content: "resposta"} in result
  end
end
