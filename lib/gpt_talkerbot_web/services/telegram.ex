defmodule GptTalkerbotWeb.Services.Telegram do
  @moduledoc """
  Client for the telegram API
  """

  use Tesla

  alias GptTalkerbot.Telegram.ClientInputs

  # defp token, do: Application.get_env(:my_scrobbles_bot, __MODULE__)[:token]

  plug Tesla.Middleware.BaseUrl,
       "https://api.telegram.org/bot#{telegram_api_key()}"

  plug Tesla.Middleware.Headers
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger, level: :warning

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

  @doc """
  Reage a uma mensagem com um emoji (setMessageReaction).
  O emoji precisa estar na lista de reações aceitas pelo Telegram.
  """
  def set_message_reaction(%{chat_id: chat_id, message_id: message_id, emoji: emoji}) do
    post("/setMessageReaction", %{
      chat_id: chat_id,
      message_id: message_id,
      reaction: [%{type: "emoji", emoji: emoji}]
    })
  end

  @doc """
  Mostra "digitando..." no chat. O status dura ~5s ou até a próxima
  mensagem do bot chegar.
  """
  def send_typing(chat_id) do
    post("/sendChatAction", %{chat_id: chat_id, action: "typing"})
  end

  @doc """
  Lista os administradores do chat — a única listagem de membros que a
  Bot API oferece.
  """
  def get_chat_administrators(chat_id) do
    case post("/getChatAdministrators", %{chat_id: chat_id}) do
      {:ok, %{status: 200, body: %{"ok" => true, "result" => admins}}} -> {:ok, admins}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Envia uma enquete (não-anônima por padrão, para render fofoca)"
  def send_poll(%{chat_id: chat_id, question: question, options: options} = params) do
    post("/sendPoll", %{
      chat_id: chat_id,
      question: question,
      options: Enum.map(options, &%{text: &1}),
      is_anonymous: Map.get(params, :is_anonymous, false)
    })
  end

  @doc "Envia a animação nativa de dado/dardo/caça-níquel etc."
  def send_dice(chat_id, emoji) do
    post("/sendDice", %{chat_id: chat_id, emoji: emoji})
  end

  @doc "Reposta um GIF pelo file_id"
  def send_animation(%{chat_id: chat_id, animation: file_id}) do
    post("/sendAnimation", %{chat_id: chat_id, animation: file_id})
  end

  @doc "Registra o menu de comandos exibido no autocomplete do Telegram"
  def set_my_commands do
    commands = [
      %{command: "humor", description: "Humor atual do rato"},
      %{command: "fatos", description: "O que ele sabe sobre você"},
      %{command: "esquece", description: "Apagar o que ele sabe sobre você"},
      %{command: "resumo", description: "Resumo debochado do grupo"},
      %{command: "enquete", description: "Enquete a partir da sua instrução"},
      %{command: "enquete_random", description: "Enquete maliciosa com o pessoal do grupo"},
      %{command: "sorte", description: "Testar a sorte do rato"},
      %{command: "ratowarn", description: "Warn oficial — responda à mensagem culpada"},
      %{command: "bangif", description: "Banir GIF da memória — responda ao GIF"}
    ]

    post("/setMyCommands", %{commands: commands})
  end

  defp build_and_send(fun, route, module, params) do
    with {:ok, input} <- module.build(params) do
      fun.(route, input)
    end
  end

  def set_maintenance_mode() do
    get("/setWebhook?url=https://example.com&drop_pending_updates=true")
  end

  def set_production_mode() do
    server = Application.get_env(:gpt_talkerbot, :server_host, "")
    set_my_commands()

    case Application.get_env(:gpt_talkerbot, :telegram_webhook_secret, "") do
      "" -> get("/setWebhook?url=#{server}&drop_pending_updates=true")
      secret -> get("/setWebhook?url=#{server}&drop_pending_updates=true&secret_token=#{secret}")
    end
  end


  def get_webhook_info() do
    get("/getWebhookInfo")
  end

  defp telegram_api_key, do: Application.get_env(:gpt_talkerbot, :telegram_api_key, "")
end
