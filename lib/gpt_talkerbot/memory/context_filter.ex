defmodule GptTalkerbot.Memory.ContextFilter do
  require Logger

  alias GptTalkerbotWeb.Services.Embeddings

  @relevance_threshold 0.4
  @always_include_last 2

  def filter([], _current_text) do
    Logger.info("ContextFilter: empty history, nothing to filter")
    []
  end

  def filter(messages, _current_text) when length(messages) <= @always_include_last do
    Logger.info("ContextFilter: #{length(messages)} messages <= always_include_last=#{@always_include_last}, skipping filter")
    strip_timestamps(messages)
  end

  def filter(messages, current_text) do
    Logger.info("ContextFilter: filtering #{length(messages)} messages threshold=#{@relevance_threshold} always_include_last=#{@always_include_last}")

    all_texts = Enum.map(messages, & &1.content) ++ [current_text]

    case Embeddings.embed_batch(all_texts) do
      {:ok, embeddings} ->
        Logger.info("ContextFilter: embeddings ok total=#{length(embeddings)}")
        result = apply_relevance_filter(messages, embeddings)
        Logger.info("ContextFilter: kept #{length(result)}/#{length(messages)} messages after filter")
        result

      {:error, reason} ->
        Logger.warning("ContextFilter: embedding failed reason=#{inspect(reason)} — returning full history")
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
    |> Enum.filter(fn {{msg, emb}, idx} ->
      score = cosine_similarity(emb, current_emb)
      forced = idx >= always_from
      included = forced or score >= @relevance_threshold
      preview = String.slice(msg.content, 0, 50)

      Logger.info("ContextFilter: idx=#{idx} score=#{Float.round(score, 3)} forced=#{forced} included=#{included} content=\"#{preview}\"")

      included
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
