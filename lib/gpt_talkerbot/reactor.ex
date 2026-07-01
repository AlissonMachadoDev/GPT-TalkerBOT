defmodule GptTalkerbot.Reactor do
  @moduledoc """
  Reações de emoji a mensagens do grupo — presença constante do rato
  a custo zero de LLM. Probabilidade em RuntimeEnvs (reaction_probability).

  O Telegram só aceita um conjunto fixo de emojis em reações; a lista
  abaixo é o subconjunto mais com cara de Ratobô.
  """

  alias GptTalkerbot.RuntimeEnvs
  alias GptTalkerbotWeb.Services.Telegram

  @emojis ["🤣", "🤔", "🔥", "🤡", "👀", "💯", "😴", "🗿", "🐳", "🍌"]

  def maybe_react(chat_id, message_id) when is_integer(message_id) do
    if :rand.uniform() < RuntimeEnvs.get_reaction_probability() do
      Task.start(fn ->
        Telegram.set_message_reaction(%{
          chat_id: chat_id,
          message_id: message_id,
          emoji: Enum.random(@emojis)
        })
      end)
    end

    :ok
  end

  def maybe_react(_chat_id, _message_id), do: :ok
end
