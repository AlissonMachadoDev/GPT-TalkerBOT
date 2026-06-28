defmodule GptTalkerbot.Memory do
  require Logger

  import Ecto.Query
  alias GptTalkerbot.Repo
  alias GptTalkerbot.Memory.{ConversationMessage, UserFact, ContextFilter}

  @max_messages 20
  @max_age_hours 4
  @session_gap_minutes 60

  # --- Conversa ---

  def get_context(chat_id, user_id, current_text) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@max_age_hours * 3600)

    raw =
      ConversationMessage
      |> where([m], m.chat_id == ^chat_id and m.user_id == ^user_id and m.inserted_at > ^cutoff)
      |> order_by([m], asc: m.inserted_at)
      |> limit(@max_messages)
      |> select([m], %{role: m.role, content: m.content, inserted_at: m.inserted_at})
      |> Repo.all()

    Logger.info("Memory.get_context: chat=#{chat_id} user=#{user_id} raw_messages=#{length(raw)} cutoff=#{@max_age_hours}h")

    trimmed = trim_to_last_session(raw)

    if length(trimmed) < length(raw) do
      Logger.info("Memory.get_context: session trim dropped #{length(raw) - length(trimmed)} messages (gap > #{@session_gap_minutes}min)")
    end

    result = ContextFilter.filter(trimmed, current_text)

    Logger.info("Memory.get_context: final context size=#{length(result)} (raw=#{length(raw)} trimmed=#{length(trimmed)} filtered=#{length(result)})")

    result
  end

  defp trim_to_last_session([]) do
    Logger.info("Memory.trim_to_last_session: empty history")
    []
  end

  defp trim_to_last_session(messages) do
    gap_seconds = @session_gap_minutes * 60

    {session_start, _} =
      Enum.with_index(messages)
      |> Enum.reduce({0, nil}, fn {msg, idx}, {last_break, prev} ->
        if prev && NaiveDateTime.diff(msg.inserted_at, prev.inserted_at) > gap_seconds do
          Logger.info("Memory.trim_to_last_session: gap detected at idx=#{idx} diff=#{NaiveDateTime.diff(msg.inserted_at, prev.inserted_at)}s")
          {idx, msg}
        else
          {last_break, msg}
        end
      end)

    Enum.drop(messages, session_start)
  end

  def save_exchange(chat_id, user_id, user_content, assistant_reply) do
    Logger.info("Memory.save_exchange: chat=#{chat_id} user=#{user_id}")

    case Repo.transaction(fn ->
      insert_message!(chat_id, user_id, "user", user_content)
      insert_message!(chat_id, user_id, "assistant", assistant_reply)
    end) do
      {:ok, _} ->
        Logger.info("Memory.save_exchange: ok chat=#{chat_id}")
        {:ok, :saved}
      {:error, reason} ->
        Logger.error("Memory.save_exchange: failed chat=#{chat_id} reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  def save_reply_exchange(chat_id, user_id, context_content, user_content, assistant_reply) do
    Logger.info("Memory.save_reply_exchange: chat=#{chat_id} user=#{user_id}")

    case Repo.transaction(fn ->
      insert_message!(chat_id, user_id, "user", context_content)
      insert_message!(chat_id, user_id, "user", user_content)
      insert_message!(chat_id, user_id, "assistant", assistant_reply)
    end) do
      {:ok, _} ->
        Logger.info("Memory.save_reply_exchange: ok chat=#{chat_id}")
        {:ok, :saved}
      {:error, reason} ->
        Logger.error("Memory.save_reply_exchange: failed chat=#{chat_id} reason=#{inspect(reason)}")
        {:error, reason}
    end
  end

  def clear_context(chat_id) do
    Logger.info("Memory.clear_context: chat=#{chat_id}")
    {count, _} = ConversationMessage
      |> where([m], m.chat_id == ^chat_id)
      |> Repo.delete_all()
    Logger.info("Memory.clear_context: deleted #{count} messages chat=#{chat_id}")
  end

  defp insert_message!(chat_id, user_id, role, content) do
    %ConversationMessage{}
    |> ConversationMessage.changeset(%{
      chat_id: chat_id,
      user_id: user_id,
      role: role,
      content: content
    })
    |> Repo.insert!()
  end

  # --- Fatos do usuário ---

  def get_user_facts(user_id) do
    facts = UserFact
      |> where([f], f.user_id == ^user_id)
      |> Repo.all()

    Logger.info("Memory.get_user_facts: user=#{user_id} facts=#{length(facts)}")
    facts
  end

  def upsert_fact(user_id, key, value) do
    Logger.info("Memory.upsert_fact: user=#{user_id} key=#{key} value=\"#{value}\"")

    %UserFact{}
    |> UserFact.changeset(%{user_id: user_id, key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]],
      conflict_target: [:user_id, :key]
    )
  end

  def clear_user_facts(user_id) do
    Logger.info("Memory.clear_user_facts: user=#{user_id}")
    {count, _} = UserFact
      |> where([f], f.user_id == ^user_id)
      |> Repo.delete_all()
    Logger.info("Memory.clear_user_facts: deleted #{count} facts user=#{user_id}")
  end
end
