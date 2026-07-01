defmodule GptTalkerbot.MoodTracker do
  @moduledoc """
  Humor do bot por chat, dirigido por eventos:

    * cadência — a cada N respostas do bot no chat, um mood aleatório entra
      (mesmos múltiplos do sistema antigo, agora por chat em vez de global)
    * insulto dirigido ao bot -> :grumpy
    * rajada de mensagens no grupo -> :excited
    * madrugada (hora local 0-5) com mood :normal -> :sleepy

  Moods não-normais duram RuntimeEnvs.get_mood_duration/0 respostas e
  decaem para :normal.
  """

  use GenServer

  alias GptTalkerbot.RuntimeEnvs

  @moods [:normal, :grumpy, :excited, :sarcastic, :sleepy]

  # Rajada: este número de mensagens do grupo dentro da janela vira :excited
  @burst_count 10
  @burst_window_seconds 60

  @insult_regex ~r/\b(burro|idiota|lixo|inútil|imprestável|merda|bosta|otário|arrombado|fdp|desgraça)\b/iu

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Mood efetivo do chat (já considera o horário para :sleepy)"
  def get_mood(chat_id) do
    GenServer.call(__MODULE__, {:get_mood, to_string(chat_id)})
  end

  @doc "Registra uma resposta do bot no chat: avança a cadência e o decay"
  def bump(chat_id) do
    GenServer.cast(__MODULE__, {:bump, to_string(chat_id)})
  end

  @doc "Registra atividade do grupo (qualquer mensagem) para detectar rajadas"
  def note_activity(chat_id) do
    GenServer.cast(__MODULE__, {:note_activity, to_string(chat_id)})
  end

  @doc "Reage ao conteúdo de uma mensagem dirigida ao bot (insulto -> :grumpy)"
  def react_to_text(chat_id, text) when is_binary(text) do
    if Regex.match?(@insult_regex, text) do
      set_mood(chat_id, :grumpy)
    end

    :ok
  end

  def react_to_text(_chat_id, _text), do: :ok

  def set_mood(chat_id, mood) when mood in @moods do
    GenServer.cast(__MODULE__, {:set_mood, to_string(chat_id), mood})
  end

  @doc "Zera o humor e contadores de todos os chats (usado pela limpeza total)"
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{}}
  end

  def handle_call({:get_mood, chat_id}, _from, state) do
    entry = Map.get(state, chat_id, new_entry())
    {:reply, effective_mood(entry.mood), state}
  end

  @impl true
  def handle_cast({:bump, chat_id}, state) do
    entry = Map.get(state, chat_id, new_entry())
    count = entry.count + 1

    {mood, remaining} =
      cond do
        rem(count, 50) == 0 -> {:grumpy, mood_duration()}
        rem(count, 35) == 0 -> {:excited, mood_duration()}
        rem(count, 20) == 0 -> {:sarcastic, mood_duration()}
        entry.remaining > 1 -> {entry.mood, entry.remaining - 1}
        true -> {:normal, 0}
      end

    {:noreply, Map.put(state, chat_id, %{entry | count: count, mood: mood, remaining: remaining})}
  end

  def handle_cast({:note_activity, chat_id}, state) do
    entry = Map.get(state, chat_id, new_entry())
    now = System.monotonic_time(:second)

    activity =
      [now | entry.activity]
      |> Enum.take_while(&(now - &1 <= @burst_window_seconds))

    entry =
      if length(activity) >= @burst_count and entry.mood == :normal do
        %{entry | activity: activity, mood: :excited, remaining: mood_duration()}
      else
        %{entry | activity: activity}
      end

    {:noreply, Map.put(state, chat_id, entry)}
  end

  def handle_cast({:set_mood, chat_id, mood}, state) do
    entry = Map.get(state, chat_id, new_entry())
    {:noreply, Map.put(state, chat_id, %{entry | mood: mood, remaining: mood_duration()})}
  end

  defp new_entry do
    %{mood: :normal, remaining: 0, count: 0, activity: []}
  end

  # Madrugada só se sobrepõe ao :normal — um mood dirigido por evento vence o sono
  defp effective_mood(:normal) do
    if local_hour() in 0..5, do: :sleepy, else: :normal
  end

  defp effective_mood(mood), do: mood

  defp local_hour do
    DateTime.utc_now()
    |> DateTime.add(RuntimeEnvs.get_utc_offset() * 3600)
    |> Map.get(:hour)
  end

  defp mood_duration, do: RuntimeEnvs.get_mood_duration()
end
