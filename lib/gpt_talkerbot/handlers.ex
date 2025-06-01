defmodule GptTalkerbot.Telegram.Handlers do
  @moduledoc """
  Behaviour for telegram message handlers.

  Also matches messages with handlers through get_handler/1
  """

  alias GptTalkerbot.Telegram.{Message}

  alias GptTalkerbot.Telegram.Handlers.{
    DefaultHandler,
    HelpHandler,
    CommandHandler,
    MessageHandler
  }

  @callback handle(Message.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Matches a message with its handler module
  """
  def get_handler(%Message{text: "/help" <> ""}), do: {:ok, HelpHandler}
  def get_handler(%Message{text: "/" <> _command}), do: {:ok, CommandHandler}
  def get_handler(_), do: {:ok, DefaultHandler}
end
