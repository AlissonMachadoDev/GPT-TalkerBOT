defmodule GptTalkerbot.Memory.ContextFilter do
  require Logger

  alias GptTalkerbot.RuntimeEnvs
  alias GptTalkerbotWeb.Services.Embeddings

  def filter([], _current_text), do: []

  def filter(messages, current_text) do
    if length(messages) <= RuntimeEnvs.get_always_include_last() do
      strip_timestamps(messages)
    else
      embed_and_filter(messages, current_text)
    end
  end

  defp embed_and_filter(messages, current_text) do
    all_texts = Enum.map(messages, & &1.content) ++ [current_text]

    case Embeddings.embed_batch(all_texts) do
      {:ok, embeddings} ->
        apply_relevance_filter(messages, embeddings)

      {:error, _} ->
        Logger.warning("ContextFilter: embedding unavailable, returning full history")
        strip_timestamps(messages)
    end
  end

  @doc false
  def apply_relevance_filter(messages, embeddings) do
    current_emb = List.last(embeddings)
    history_embs = Enum.drop(embeddings, -1)
    total = length(messages)
    always_from = total - RuntimeEnvs.get_always_include_last()
    threshold = RuntimeEnvs.get_relevance_threshold()

    scored =
      messages
      |> Enum.zip(history_embs)
      |> Enum.with_index()
      |> Enum.map(fn {{msg, emb}, idx} ->
        {Map.take(msg, [:role, :content]), cosine_similarity(emb, current_emb), idx >= always_from}
      end)

    {result, _} =
      Enum.reduce(scored, {[], false}, fn {msg, score, forced}, {acc, prev_included} ->
        include =
          case msg.role do
            "assistant" -> prev_included or forced
            _ -> forced or score >= threshold
          end

        {if(include, do: acc ++ [msg], else: acc), include}
      end)

    result
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
