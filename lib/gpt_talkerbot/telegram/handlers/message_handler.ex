defmodule GptTalkerbot.Telegram.Handlers.MessageHandler do
  @moduledoc """
  Sends a simple help message
  """

  alias GptTalkerbot.Telegram.Message
  alias GptTalkerbotWeb.Services.{Telegram, OpenAI}
  alias GptTalkerbot.Access

  @behaviour GptTalkerbot.Telegram.Handlers
  def api_key, do: Application.get_env(:gpt_talkerbot, :openai_api_key, "")

  @impl true
  def handle(%Message{
        chat_id: chat_id,
        text: text,
        chat_type: "private_temp",
        from: %{telegram_id: user_id}
      }) do
    with user <- Access.get_user_by_telegram_id!(user_id),
         {:ok, api_key} <- Access.get_key_for_user(user) do
      process_gpt_message(api_key, text, chat_id, user_id)
    else
      {:error, :no_access} -> send_message(chat_id, "Você não tem acesso ao bot")
      _ -> send_message(chat_id, "Ocorreu um erro")
    end
  end

  def handle(%Message{
        chat_id: chat_id,
        text: text,
        chat_type: group,
        from: %{telegram_id: user_id}
      })
      when group in ["group_temp", "supergroup_temp"] do
    with {:ok, api_key} <- Access.get_key_for_group(chat_id) do
      process_gpt_message(api_key, text, chat_id, user_id)
    else
      {:error, :group_not_registered} -> send_message(chat_id, "Grupo não registrado")
      _ -> send_message(chat_id, "Ocorreu um erro")
    end
  end

  def handle(%Message{
        chat_id: chat_id,
        text: text,
        from: %{telegram_id: user_id}
      }) do
    process_gpt_message(api_key(), text, chat_id, user_id)
  end

  defp process_gpt_message(api_key, text, chat_id, user_id) do
    api_key
    |> OpenAI.new()
    |> OpenAI.gpt_completion(text, user_id)
    |> case do
      {:ok, response} -> handle_gpt_response(response, chat_id)
      {:error, _} -> send_message(chat_id, "Erro ao processar mensagem")
    end
  end

  defp handle_gpt_response(response, chat_id) do
    response
    |> Map.get("choices")
    |> List.first()
    |> Map.get("message")
    |> Map.get("content")
    |> String.split_at(3500)
    |> Tuple.to_list()
    |> Enum.each(&send_message(chat_id, &1))
  end

  defp send_message(chat_id, text) do
    Telegram.send_message(%{chat_id: chat_id, text: text})
  end
end
