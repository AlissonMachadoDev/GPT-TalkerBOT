defmodule GptTalkerbot.GroupMessageCache do
  use GenServer

  require Logger

  import Ecto.Query

  alias GptTalkerbot.Repo
  alias GptTalkerbot.Memory.GroupMessage

  @buffer_limit 50
  @extraction_batch 20
  @bot_name "Ratobô"

  # As mensagens ficam retidas como "log do dia" (fonte do resumo diário) e são
  # envelhecidas depois desse prazo, independente de já terem sido resumidas
  @retention_hours 48
  @cleanup_interval_ms 6 * 60 * 60 * 1_000

  # Teto de mensagens que o resumo diário lê por chat, para o prompt não estourar
  # em grupos muito movimentados
  @daily_read_limit 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_message(chat_id, sender_name, content) do
    chat_id = to_string(chat_id)

    # Checagem no processo chamador: o filtro de /ignore_messages não pode
    # custar um roundtrip pelo GenServer em toda mensagem do grupo
    if GptTalkerbot.IgnoredPatterns.ignored?(chat_id, content) do
      :ok
    else
      GenServer.cast(__MODULE__, {:add_message, chat_id, sender_name, content})
    end
  end

  def add_bot_message(chat_id, content) do
    add_message(chat_id, @bot_name, content)
  end

  def get_recent(chat_id, count \\ 10) do
    GenServer.call(__MODULE__, {:get_recent, to_string(chat_id), count})
  end

  @doc "Descarta os buffers de todos os chats (usado pela limpeza total)"
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Remove do buffer (e do espelho persistido) as mensagens do chat com esse
  conteúdo — comparação sem tags HTML, igual à Memory.forget_by_content/2.
  Retorna quantas saíram do buffer.
  """
  def forget(chat_id, content) do
    GenServer.call(__MODULE__, {:forget, to_string(chat_id), content})
  end

  @doc "Esvazia o buffer de um único chat (e o espelho persistido dele)"
  def clear(chat_id) do
    GenServer.call(__MODULE__, {:clear, to_string(chat_id)})
  end

  @doc """
  Mensagens do chat a partir de `cutoff` (`DateTime`), em ordem cronológica.
  Inclui as já resumidas — é o log cru que alimenta o resumo diário. Limitado
  às `#{@daily_read_limit}` mais recentes da janela.
  """
  def messages_since(chat_id, %DateTime{} = cutoff) do
    GroupMessage
    |> where([m], m.chat_id == ^to_string(chat_id) and m.inserted_at >= ^cutoff)
    |> order_by([m], desc: m.inserted_at)
    |> limit(@daily_read_limit)
    |> select([m], %{sender_name: m.sender_name, content: m.content, inserted_at: m.inserted_at})
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  Formata mensagens (as retornadas por `messages_since/2`) como transcrição
  legível `[HH:MM] Nome: texto`, para alimentar prompts de resumo.
  """
  def format_transcript(messages) do
    Enum.map_join(messages, "\n", fn m ->
      ts = m.inserted_at |> NaiveDateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
      "[#{ts}] #{m.sender_name}: #{m.content}"
    end)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cutoff = DateTime.utc_now() |> DateTime.add(-@retention_hours * 3600)
    count = purge_older_than(cutoff)

    if count > 0, do: Logger.info("GroupMessageCache: envelheceu #{count} mensagens antigas")

    schedule_cleanup()
    {:noreply, state}
  end

  @doc false
  def purge_older_than(%DateTime{} = cutoff) do
    {count, _} =
      GroupMessage
      |> where([m], m.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{}}
  end

  def handle_call({:get_recent, chat_id, count}, _from, state) do
    {messages, state} = ensure_loaded(state, chat_id)
    recent = messages |> Enum.take(-count)
    {:reply, recent, state}
  end

  def handle_call({:clear, chat_id}, _from, state) do
    GroupMessage
    |> where([m], m.chat_id == ^chat_id)
    |> Repo.delete_all()

    {:reply, :ok, Map.put(state, chat_id, [])}
  end

  def handle_call({:forget, chat_id, content}, _from, state) do
    target = GptTalkerbot.Memory.normalize_content(content)

    {messages, state} = ensure_loaded(state, chat_id)

    {removed, kept} =
      Enum.split_with(messages, &(GptTalkerbot.Memory.normalize_content(&1.content) == target))

    unless removed == [] do
      contents = removed |> Enum.map(& &1.content) |> Enum.uniq()

      GroupMessage
      |> where([m], m.chat_id == ^chat_id and m.content in ^contents)
      |> Repo.delete_all()
    end

    {:reply, length(removed), Map.put(state, chat_id, kept)}
  end

  @impl true
  def handle_cast({:add_message, chat_id, sender_name, content}, state) do
    Task.start(fn -> persist_message(chat_id, sender_name, content) end)

    message = %{
      sender_name: sender_name,
      content: content,
      inserted_at: NaiveDateTime.utc_now()
    }

    {loaded, state} = ensure_loaded(state, chat_id)
    messages = loaded ++ [message]

    new_state =
      if length(messages) >= @buffer_limit do
        {to_extract, to_keep} = Enum.split(messages, @extraction_batch)
        trigger_extraction(chat_id, to_extract)
        Map.put(state, chat_id, to_keep)
      else
        Map.put(state, chat_id, messages)
      end

    {:noreply, new_state}
  end

  # Recupera do banco as mensagens persistidas antes do último restart
  defp ensure_loaded(state, chat_id) do
    case Map.fetch(state, chat_id) do
      {:ok, messages} ->
        {messages, state}

      :error ->
        messages = load_recent_from_db(chat_id)
        {messages, Map.put(state, chat_id, messages)}
    end
  end

  defp persist_message(chat_id, sender_name, content) do
    %GroupMessage{}
    |> GroupMessage.changeset(%{chat_id: chat_id, sender_name: sender_name, content: content})
    |> Repo.insert()
  end

  defp trigger_extraction(chat_id, messages) do
    Task.start(fn ->
      GptTalkerbot.PromptSettings.GroupContextExtractor.extract_and_update(chat_id, messages)
      mark_processed(chat_id, messages)
    end)
  end

  # Antes as mensagens resumidas eram apagadas; agora ficam retidas como log do
  # dia e só são marcadas, para não voltarem ao buffer nem serem resumidas de novo
  defp mark_processed(chat_id, messages) do
    oldest_ts = messages |> List.first() |> Map.get(:inserted_at)
    newest_ts = messages |> List.last() |> Map.get(:inserted_at)

    GroupMessage
    |> where(
      [m],
      m.chat_id == ^chat_id and m.inserted_at >= ^oldest_ts and m.inserted_at <= ^newest_ts and
        is_nil(m.processed_at)
    )
    |> Repo.update_all(set: [processed_at: DateTime.utc_now()])
  end

  defp load_recent_from_db(chat_id) do
    GroupMessage
    |> where([m], m.chat_id == ^chat_id and is_nil(m.processed_at))
    |> order_by([m], desc: m.inserted_at)
    |> limit(@buffer_limit)
    |> select([m], %{sender_name: m.sender_name, content: m.content, inserted_at: m.inserted_at})
    |> Repo.all()
    |> Enum.reverse()
  end
end
