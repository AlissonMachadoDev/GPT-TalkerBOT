defmodule GptTalkerbot.MoodTracker do
  @moduledoc """
  Humor global do bot, sorteado aleatoriamente a cada 6 horas.

  Um mood entra em vigor por uma janela de 6h e então é re-sorteado (nunca
  repetindo o anterior, para a troca ser sempre perceptível). Todos os moods
  são apenas de tom: modulam a voz das respostas sem nunca cortar conteúdo nem
  encurtar o que foi pedido.

  A lista @moods deve ser mantida em sincronia com @mood_suffixes em
  GptTalkerbot.PromptSettings.Personality e @mood_lines em
  GptTalkerbot.Telegram.RatoCommands.
  """

  use GenServer

  require Logger

  @moods [
    :normal,
    :grumpy,
    :excited,
    :sarcastic,
    :flertando,
    :nostalgico,
    :fofoqueiro,
    :dramatico
  ]

  @rotation_interval_ms 6 * 60 * 60 * 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Mood global vigente. O chat_id é ignorado — o humor é o mesmo para todos."
  def get_mood(_chat_id \\ nil) do
    GenServer.call(__MODULE__, :get_mood)
  end

  @doc "Re-sorteia o mood imediatamente e retorna o novo mood"
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    schedule_rotation()
    {:ok, %{mood: roll(:normal)}}
  end

  @impl true
  def handle_call(:get_mood, _from, state) do
    {:reply, state.mood, state}
  end

  def handle_call(:reset, _from, state) do
    mood = roll(state.mood)
    {:reply, mood, %{state | mood: mood}}
  end

  @impl true
  def handle_info(:rotate, state) do
    mood = roll(state.mood)
    Logger.info("MoodTracker: novo humor sorteado -> #{mood}")
    schedule_rotation()
    {:noreply, %{state | mood: mood}}
  end

  # Sorteia um mood diferente do atual para que cada janela tenha um humor novo
  defp roll(current) do
    case @moods -- [current] do
      [] -> current
      others -> Enum.random(others)
    end
  end

  defp schedule_rotation do
    Process.send_after(self(), :rotate, @rotation_interval_ms)
  end
end
