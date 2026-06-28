defmodule GptTalkerbot.Memory.ContextFilter do
  require Logger

  alias GptTalkerbotWeb.Services.Embeddings

  # Similaridade mínima para incluir uma mensagem do histórico
  @relevance_threshold 0.4

  # Últimas N mensagens sempre incluídas, independente do score
  # (preserva o fluxo imediato da conversa)
  @always_include_last 4

  def filter([], _current_text), do: []

  def filter(messages, _current_text) when length(messages) <= @always_include_last do
    strip_timestamps(messages)
  end

  def filter(messages, current_text) do
    all_texts = Enum.map(messages, & &1.content) ++ [current_text]

    case Embeddings.embed_batch(all_texts) do
      {:ok, embeddings} ->
        apply_relevance_filter(messages, embeddings)

      {:error, _} ->
        Logger.warning("ContextFilter: embedding unavailable, returning full history")
        strip_timestamps(messages)
    end
  end

  defp apply_relevance_filter(messages, embeddings) do
    current_emb = List.last(embeddings)
    history_embs = Enum.drop(embeddings, -1)
    total = length(messages)
    always_from = total - @always_include_last

    messages
    |> Enum.zip(history_embs)
    |> Enum.with_index()
    |> Enum.filter(fn {{_msg, emb}, idx} ->
      idx >= always_from or cosine_similarity(emb, current_emb) >= @relevance_threshold
    end)
    |> Enum.map(fn {{msg, _emb}, _idx} -> Map.take(msg, [:role, :content]) end)
  end

  defp strip_timestamps(messages) do
    Enum.map(messages, &Map.take(&1, [:role, :content]))
  end

  defp cosine_similarity(a, b) do
    dot = Enum.zip(a, b) |> Enum.reduce(0.0, fn {x, y}, acc -> acc + x * y end)
    mag_a = :math.sqrt(Enum.reduce(a, 0.0, fn x, acc -> acc + x * x end))
    mag_b = :math.sqrt(Enum.reduce(b, 0.0, fn x, acc -> acc + x * x end))
    if mag_a * mag_b == 0.0, do: 0.0, else: dot / (mag_a * mag_b)
  end
end
