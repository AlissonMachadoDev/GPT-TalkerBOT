defmodule GptTalkerbot.Memory do
  import Ecto.Query
  alias GptTalkerbot.Repo
  alias GptTalkerbot.Memory.{ConversationMessage, UserFact, ContextFilter}

  @max_messages 20
  @max_age_hours 4
  @session_gap_minutes 60

  # --- Conversa ---

  def get_context(chat_id, user_id, current_text) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@max_age_hours * 3600)

    ConversationMessage
    |> where([m], m.chat_id == ^chat_id and m.user_id == ^user_id and m.inserted_at > ^cutoff)
    |> order_by([m], asc: m.inserted_at)
    |> limit(@max_messages)
    |> select([m], %{role: m.role, content: m.content, inserted_at: m.inserted_at})
    |> Repo.all()
    |> trim_to_last_session()
    |> ContextFilter.filter(current_text)
  end

  defp trim_to_last_session([]), do: []
  defp trim_to_last_session(messages) do
    gap_seconds = @session_gap_minutes * 60

    {session_start, _} =
      Enum.with_index(messages)
      |> Enum.reduce({0, nil}, fn {msg, idx}, {last_break, prev} ->
        if prev && NaiveDateTime.diff(msg.inserted_at, prev.inserted_at) > gap_seconds do
          {idx, msg}
        else
          {last_break, msg}
        end
      end)

    messages
    |> Enum.drop(session_start)
    |> Enum.map(&Map.take(&1, [:role, :content]))
  end

  def save_exchange(chat_id, user_id, user_content, assistant_reply) do
    Repo.transaction(fn ->
      insert_message!(chat_id, user_id, "user", user_content)
      insert_message!(chat_id, user_id, "assistant", assistant_reply)
    end)
  end

  def save_reply_exchange(chat_id, user_id, context_content, user_content, assistant_reply) do
    Repo.transaction(fn ->
      insert_message!(chat_id, user_id, "user", context_content)
      insert_message!(chat_id, user_id, "user", user_content)
      insert_message!(chat_id, user_id, "assistant", assistant_reply)
    end)
  end

  def clear_context(chat_id) do
    ConversationMessage
    |> where([m], m.chat_id == ^chat_id)
    |> Repo.delete_all()
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
    UserFact
    |> where([f], f.user_id == ^user_id)
    |> Repo.all()
  end

  def upsert_fact(user_id, key, value) do
    %UserFact{}
    |> UserFact.changeset(%{user_id: user_id, key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]],
      conflict_target: [:user_id, :key]
    )
  end

  def clear_user_facts(user_id) do
    UserFact
    |> where([f], f.user_id == ^user_id)
    |> Repo.delete_all()
  end
end
