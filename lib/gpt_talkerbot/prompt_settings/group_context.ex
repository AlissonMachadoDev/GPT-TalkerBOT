defmodule GptTalkerbot.PromptSettings.GroupContext do
  use GenServer

  require Logger

  import Ecto.Query

  alias GptTalkerbot.Repo
  alias GptTalkerbot.PromptSettings.GroupContextSchema

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_context(chat_id) do
    GenServer.call(__MODULE__, {:get_context, to_string(chat_id)})
  end

  def update_context(chat_id, context) do
    GenServer.cast(__MODULE__, {:update_context, to_string(chat_id), context})
  end

  @impl true
  def init(_opts) do
    Logger.info("GroupContext: started")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_context, chat_id}, _from, state) do
    case Map.get(state, chat_id) do
      nil ->
        Logger.info("GroupContext: cache miss chat=#{chat_id} — loading from DB")
        context = load_from_db(chat_id)

        if context == "" do
          Logger.info("GroupContext: no context in DB yet chat=#{chat_id}")
        else
          Logger.info("GroupContext: loaded from DB chat=#{chat_id} length=#{String.length(context)}")
        end

        {:reply, context, Map.put(state, chat_id, context)}

      context ->
        Logger.info("GroupContext: cache hit chat=#{chat_id} length=#{String.length(context)}")
        {:reply, context, state}
    end
  end

  @impl true
  def handle_cast({:update_context, chat_id, context}, state) do
    Logger.info("GroupContext: updating chat=#{chat_id} new_length=#{String.length(context)}")
    Logger.info("GroupContext: new context chat=#{chat_id} content=\"#{String.slice(context, 0, 120)}...\"")

    Task.start(fn ->
      Logger.info("GroupContext: persisting to DB chat=#{chat_id}")
      case persist_to_db(chat_id, context) do
        {:ok, _} ->
          Logger.info("GroupContext: DB persist ok chat=#{chat_id}")
        {:error, changeset} ->
          Logger.error("GroupContext: DB persist failed chat=#{chat_id} errors=#{inspect(changeset.errors)}")
      end
    end)

    {:noreply, Map.put(state, chat_id, context)}
  end

  defp load_from_db(chat_id) do
    case Repo.one(from g in GroupContextSchema, where: g.chat_id == ^chat_id) do
      nil ->
        Logger.info("GroupContext: no DB record found chat=#{chat_id}")
        ""
      record ->
        Logger.info("GroupContext: DB record found chat=#{chat_id} updated_at=#{record.updated_at}")
        record.context
    end
  end

  defp persist_to_db(chat_id, context) do
    %GroupContextSchema{}
    |> GroupContextSchema.changeset(%{chat_id: chat_id, context: context})
    |> Repo.insert(
      on_conflict: [set: [context: context, updated_at: DateTime.utc_now()]],
      conflict_target: :chat_id
    )
  end
end
