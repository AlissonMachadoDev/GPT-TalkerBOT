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
  def handle(
        %Message{
          text: text,
          chat_type: "private_temp",
          from: %{telegram_id: user_id}
        } = message
      ) do
    with user <- Access.get_user_by_telegram_id!(user_id),
         {:ok, api_key} <- Access.get_key_for_user(user) do
      process_gpt_message(api_key, user_id, []) # TODO: NEED TO BE REFACTORED
      |> case do
        {:ok, response} ->
          handle_gpt_response(response)
          |> send_message(message)

        {:error, _} ->
          send_message("Erro ao processar mensagem", message)
      end
    else
      {:error, :no_access} -> send_message("Você não tem acesso ao bot", message)
      _ -> send_message("Ocorreu um erro", message)
    end
  end

  def handle(
        %Message{
          chat_id: chat_id,
          text: text,
          chat_type: group,
          from: %{telegram_id: user_id}
        } = message
      )
      when group in ["group_temp", "supergroup_temp"] do
    with {:ok, api_key} <- Access.get_key_for_group(chat_id) do
      process_gpt_message(api_key, user_id, []) # TODO: NEED TO BE REFACTORED
      |> case do
        {:ok, response} ->
          handle_gpt_response(response)
          |> send_message(message)

        {:error, _} ->
          send_message("Erro ao processar mensagem", message)
      end
    else
      {:error, :group_not_registered} -> send_message("Grupo não registrado", message)
      _ -> send_message("Ocorreu um erro", message)
    end
  end

  def handle(
        %Message{
          text: text,
          from: %{telegram_id: user_id},
          reply_to_message: %{text: reply_text, from: %{telegram_id: reply_user_id}}
        } = message
      ) do
    with messages <- build_messages([%{user: reply_user_id,  text: reply_text}, %{user: user_id, text: text}]),
         {:ok, response} <- process_gpt_message(api_key(), user_id, messages) do
      handle_gpt_response(response)
      |> send_message(message)
    else
      {:error, _} ->
        send_message("Erro ao processar mensagem", message)
    end
  end


  def handle(
        %Message{
          text: text,
          from: %{telegram_id: user_id}
        } = message
      ) do
    with messages <- build_messages(%{user: user_id, text: text}),
         {:ok, response} <- process_gpt_message(api_key(), user_id, messages) do
      handle_gpt_response(response)
      |> send_message(message)
    else
      {:error, _} ->
        send_message("Erro ao processar mensagem", message)
    end
  end

  defp process_gpt_message(api_key, user_id, messages) do
    api_key
    |> OpenAI.new()
    |> OpenAI.gpt_completion(user_id, messages)
  end

  defp handle_gpt_response(response) do
    response
    |> Map.get("choices")
    |> List.first()
    |> Map.get("message")
    |> Map.get("content")
    |> String.split_at(3500)
    |> Tuple.to_list()
    |> List.first()
  end

  defp send_message(text, %{chat_id: chat_id, message_id: message_id}) do
    Telegram.send_message(%{chat_id: chat_id, text: text, reply_to_message_id: message_id})
  end


  def build_messages(%{user: user, text: text}) do
    [build_message(text, user)]
  end

  def build_messages([_message, _reply_message] = messages) when is_list(messages) do
    messages
    |> Enum.map(&build_message(&1.text, &1.user))
  end

  defp build_message(text, user) do
    %{role: "user", content: "user #{user}: #{text}"}
  end
end
