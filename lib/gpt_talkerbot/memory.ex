defmodule GptTalkerbot.Memory do
  import Ecto.Query
  alias GptTalkerbot.Repo
  alias GptTalkerbot.RuntimeEnvs
  alias GptTalkerbot.Memory.{ConversationMessage, UserFact, ContextFilter, GroupMessage}
  alias GptTalkerbot.PromptSettings.GroupContextSchema

  # --- Conversa ---

  def get_context(chat_id, user_id, current_text) do
    max_messages = RuntimeEnvs.get_max_context_messages()

    # Sem corte por idade: o recorte fica por conta do teto de mensagens e do
    # trim_to_last_session (gap de sessão)
    ConversationMessage
    |> where([m], m.chat_id == ^chat_id and m.user_id == ^user_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^max_messages)
    |> select([m], %{role: m.role, content: m.content, inserted_at: m.inserted_at})
    |> Repo.all()
    |> Enum.reverse()
    |> trim_to_last_session()
    |> ContextFilter.filter(current_text)
  end

  @doc false
  def trim_to_last_session([]), do: []

  def trim_to_last_session(messages) do
    gap_seconds = RuntimeEnvs.get_session_gap_minutes() * 60

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
    # Mensagem sob /ignore_messages não entra na memória de conversa; a
    # resposta vai junto porque sem a pergunta ela vira fala sem contexto
    if GptTalkerbot.IgnoredPatterns.ignored?(chat_id, user_content) do
      {:ok, :ignored}
    else
      Repo.transaction(fn ->
        insert_message!(chat_id, user_id, "user", user_content)
        insert_message!(chat_id, user_id, "assistant", assistant_reply)
      end)
    end
  end

  def clear_context(chat_id) do
    ConversationMessage
    |> where([m], m.chat_id == ^chat_id)
    |> Repo.delete_all()
  end

  # Janela de busca do forget_by_content: o alvo é sempre coisa recente
  @forget_scan_limit 200

  @doc """
  Apaga do histórico do chat as mensagens com exatamente esse conteúdo
  (qualquer role — a resposta podre e os reenvios dela). A comparação
  ignora tags HTML e espaços das pontas, porque o Telegram devolve o texto
  exibido sem as tags que foram enviadas. Retorna quantas apagou.
  """
  def forget_by_content(chat_id, text) do
    target = normalize_content(text)

    ids =
      ConversationMessage
      |> where([m], m.chat_id == ^chat_id)
      |> order_by([m], desc: m.inserted_at)
      |> limit(@forget_scan_limit)
      |> Repo.all()
      |> Enum.filter(&(normalize_content(&1.content) == target))
      |> Enum.map(& &1.id)

    {count, _} =
      ConversationMessage
      |> where([m], m.id in ^ids)
      |> Repo.delete_all()

    count
  end

  @doc false
  def normalize_content(text) do
    text
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
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

  # Sem limite o system prompt incha indefinidamente com o uso contínuo
  @max_facts 20

  def get_user_facts(user_id) do
    UserFact
    |> where([f], f.user_id == ^user_id)
    |> order_by([f], desc: f.updated_at)
    |> limit(@max_facts)
    |> Repo.all()
  end

  def upsert_fact(user_id, key, value) do
    result =
      %UserFact{}
      |> UserFact.changeset(%{user_id: user_id, key: key, value: value})
      |> Repo.insert(
        on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]],
        conflict_target: [:user_id, :key]
      )

    trim_facts(user_id)
    result
  end

  defp trim_facts(user_id) do
    ids_to_keep =
      UserFact
      |> where([f], f.user_id == ^user_id)
      |> order_by([f], desc: f.updated_at)
      |> limit(@max_facts)
      |> select([f], f.id)

    UserFact
    |> where([f], f.user_id == ^user_id and f.id not in subquery(ids_to_keep))
    |> Repo.delete_all()
  end

  def clear_user_facts(user_id) do
    UserFact
    |> where([f], f.user_id == ^user_id)
    |> Repo.delete_all()
  end

  # --- Limpeza total ---

  @doc """
  Apaga toda a memória do bot: conversas, fatos, buffer de grupo e contextos,
  incluindo os caches em memória. As tabelas de registro legadas
  (users/groups/commands) ficam intactas.
  """
  def wipe_all do
    Repo.delete_all(ConversationMessage)
    Repo.delete_all(UserFact)
    Repo.delete_all(GroupMessage)
    Repo.delete_all(GroupContextSchema)

    GptTalkerbot.GroupMessageCache.reset()
    GptTalkerbot.PromptSettings.GroupContext.reset()
    GptTalkerbot.MoodTracker.reset()

    :ok
  end
end
