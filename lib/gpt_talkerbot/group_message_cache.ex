defmodule GptTalkerbot.GroupMessageCache do
  use GenServer

  require Logger

  import Ecto.Query

  alias GptTalkerbot.Repo
  alias GptTalkerbot.Memory.GroupMessage

  @buffer_limit 50
  @extraction_batch 20
  @bot_name "Ratobô"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_message(chat_id, sender_name, content) do
    GenServer.cast(__MODULE__, {:add_message, to_string(chat_id), sender_name, content})
  end

  def add_bot_message(chat_id, content) do
    add_message(chat_id, @bot_name, content)
  end

  def get_recent(chat_id, count \\ 10) do
    GenServer.call(__MODULE__, {:get_recent, to_string(chat_id), count})
  end

  @impl true
  def init(_opts) do
    Logger.info("GroupMessageCache: started, buffer_limit=#{@buffer_limit} extraction_batch=#{@extraction_batch}")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_recent, chat_id, count}, _from, state) do
    messages = Map.get(state, chat_id, [])
    recent = Enum.take(messages, -count)
    Logger.info("GroupMessageCache: get_recent chat=#{chat_id} requested=#{count} available=#{length(messages)} returning=#{length(recent)}")
    {:reply, recent, state}
  end

  @impl true
  def handle_cast({:add_message, chat_id, sender_name, content}, state) do
    preview = String.slice(content, 0, 60)
    Logger.info("GroupMessageCache: add_message chat=#{chat_id} sender=#{sender_name} content=\"#{preview}\"")

    Task.start(fn ->
      Logger.info("GroupMessageCache: persisting to DB chat=#{chat_id} sender=#{sender_name}")
      case persist_message(chat_id, sender_name, content) do
        {:ok, _} ->
          Logger.info("GroupMessageCache: DB insert ok chat=#{chat_id}")
        {:error, changeset} ->
          Logger.warning("GroupMessageCache: DB insert failed chat=#{chat_id} errors=#{inspect(changeset.errors)}")
      end
    end)

    message = %{
      sender_name: sender_name,
      content: content,
      inserted_at: NaiveDateTime.utc_now()
    }

    messages = Map.get(state, chat_id, []) ++ [message]
    buffer_size = length(messages)
    Logger.info("GroupMessageCache: buffer chat=#{chat_id} size=#{buffer_size}/#{@buffer_limit}")

    new_state =
      if buffer_size >= @buffer_limit do
        Logger.info("GroupMessageCache: buffer full chat=#{chat_id} size=#{buffer_size} — splitting #{@extraction_batch} for extraction")
        {to_extract, to_keep} = Enum.split(messages, @extraction_batch)
        Logger.info("GroupMessageCache: triggering extraction chat=#{chat_id} extracting=#{length(to_extract)} keeping=#{length(to_keep)}")
        trigger_extraction(chat_id, to_extract)
        Map.put(state, chat_id, to_keep)
      else
        Map.put(state, chat_id, messages)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:load_from_db, chat_id}, state) do
    Logger.info("GroupMessageCache: loading from DB chat=#{chat_id}")
    messages = load_recent_from_db(chat_id)
    Logger.info("GroupMessageCache: loaded #{length(messages)} messages from DB chat=#{chat_id}")
    {:noreply, Map.put(state, chat_id, messages)}
  end

  defp persist_message(chat_id, sender_name, content) do
    %GroupMessage{}
    |> GroupMessage.changeset(%{chat_id: chat_id, sender_name: sender_name, content: content})
    |> Repo.insert()
  end

  defp trigger_extraction(chat_id, messages) do
    Task.start(fn ->
      Logger.info("GroupMessageCache: extraction task started chat=#{chat_id} messages=#{length(messages)}")

      try do
        GptTalkerbot.PromptSettings.GroupContextExtractor.extract_and_update(chat_id, messages)
        Logger.info("GroupMessageCache: extraction complete, deleting from DB chat=#{chat_id}")
        {count, _} = delete_processed_from_db(chat_id, messages)
        Logger.info("GroupMessageCache: deleted #{count} messages from DB chat=#{chat_id}")
      rescue
        e ->
          Logger.error("GroupMessageCache: extraction task crashed chat=#{chat_id} error=#{Exception.message(e)}")
      end
    end)
  end

  defp delete_processed_from_db(chat_id, messages) do
    oldest_ts = messages |> List.first() |> Map.get(:inserted_at)
    newest_ts = messages |> List.last() |> Map.get(:inserted_at)
    Logger.info("GroupMessageCache: deleting DB rows chat=#{chat_id} from=#{oldest_ts} to=#{newest_ts}")

    GroupMessage
    |> where([m], m.chat_id == ^chat_id and m.inserted_at >= ^oldest_ts and m.inserted_at <= ^newest_ts)
    |> Repo.delete_all()
  end

  defp load_recent_from_db(chat_id) do
    GroupMessage
    |> where([m], m.chat_id == ^chat_id)
    |> order_by([m], asc: m.inserted_at)
    |> limit(@buffer_limit)
    |> select([m], %{sender_name: m.sender_name, content: m.content, inserted_at: m.inserted_at})
    |> Repo.all()
  end
end
