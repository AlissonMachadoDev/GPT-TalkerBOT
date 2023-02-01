defmodule GptTalkerbotWeb.Services.Telegram do
  @moduledoc """
  Client for the telegram API
  """

  use Tesla

  alias GptTalkerbot.Telegram.ClientInputs

  # defp token, do: Application.get_env(:my_scrobbles_bot, __MODULE__)[:token]

  plug Tesla.Middleware.BaseUrl,
       "https://api.telegram.org/bot#{Application.fetch_env!(:gpt_talkerbot, :telegram_api_key)}"

  plug Tesla.Middleware.Headers
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger, log_level: :warn

  @doc """
  Calls the sendMessage method in the telegram api
  """
  def send_message(params) do
    build_and_send(&post/2, "/sendMessage", ClientInputs.SendMessage, params)
  end

  def send_inline(params) do
    build_and_send(&post/2, "/answerInlineQuery", ClientInputs.AnswerInlineQuery, params)
  end

  def send_photo(params) do
    build_and_send(&post/2, "/sendPhoto", ClientInputs.SendPhoto, params)
  end

  defp build_and_send(fun, route, module, params) do
    IO.inspect(route, label: "the route")
    with {:ok, input} <- module.build(params) do
      fun.(route, input)
    end
  end
end
