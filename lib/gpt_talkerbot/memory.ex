defmodule GptTalkerbot.Memory do
  import Ecto.Query
  alias GptTalkerbot.Repo
  alias GptTalkerbot.Memory.{ConversationMessage, UserFact}

  @max_messages 20
  @max_age_hours 4

  # --- Conversa ---

  def get_context(chat_id, user_id) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@max_age_hours * 3600)

    ConversationMessage
    |> where([m], m.chat_id == ^chat_id and m.user_id == ^user_id and m.inserted_at > ^cutoff)
    |> order_by([m], asc: m.inserted_at)
    |> limit(@max_messages)
    |> select([m], %{role: m.role, content: m.content})
    |> Repo.all()
  end

  def save_exchange(chat_id, user_id, user_content, assistant_reply) do
    Repo.transaction(fn ->
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
