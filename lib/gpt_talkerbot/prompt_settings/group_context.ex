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
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_context, chat_id}, _from, state) do
    case Map.get(state, chat_id) do
      nil ->
        context = load_from_db(chat_id)
        {:reply, context, Map.put(state, chat_id, context)}

      context ->
        {:reply, context, state}
    end
  end

  @impl true
  def handle_cast({:update_context, chat_id, context}, state) do
    Task.start(fn -> persist_to_db(chat_id, context) end)
    {:noreply, Map.put(state, chat_id, context)}
  end

  defp load_from_db(chat_id) do
    case Repo.one(from g in GroupContextSchema, where: g.chat_id == ^chat_id) do
      nil -> ""
      record -> record.context
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
