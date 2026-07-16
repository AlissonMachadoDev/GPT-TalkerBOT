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

  @doc """
  Envia uma enquete (não-anônima por padrão, para render fofoca).

  Cada opção pode ser uma string ou um mapa InputPollOption — com
  `media: %{type: "photo", media: file_id}` a opção sai ilustrada
  (Bot API 10.0+). Aceita também `media` (mídia da pergunta),
  `members_only` e `allows_multiple_answers`.
  """
  def send_poll(%{chat_id: chat_id, question: question, options: options} = params) do
    body =
      %{
        chat_id: chat_id,
        question: question,
        options: Enum.map(options, &poll_option/1),
        is_anonymous: Map.get(params, :is_anonymous, false)
      }
      |> maybe_put(:media, params[:media])
      |> maybe_put(:members_only, params[:members_only])
      |> maybe_put(:allows_multiple_answers, params[:allows_multiple_answers])

    post("/sendPoll", body)
  end

  @doc false
  def poll_option(text) when is_binary(text), do: %{text: text}
  def poll_option(%{} = option), do: option

  @doc """
  Envia uma rich message (Bot API 10.1+). `rich_message` é um
  InputRichMessage: `%{html: ...}`, `%{markdown: ...}` ou `%{blocks: [...]}`.
  """
  def send_rich_message(%{chat_id: chat_id, rich_message: rich_message} = params) do
    body =
      %{chat_id: chat_id, rich_message: rich_message}
      |> maybe_put(:reply_parameters, params[:reply_parameters])
      |> maybe_put(:disable_notification, params[:disable_notification])

    post("/sendRichMessage", body)
  end

  @doc """
  Streama um rascunho de rich message — preview efêmero de ~30s, aceito
  apenas em chat privado. Precisa ser finalizado com sendRichMessage,
  senão o rascunho evapora.
  """
  def send_rich_message_draft(%{chat_id: chat_id, draft_id: draft_id, rich_message: rich_message}) do
    post("/sendRichMessageDraft", %{
      chat_id: chat_id,
      draft_id: draft_id,
      rich_message: rich_message
    })
  end

  @doc """
  file_id da foto de perfil atual do usuário, ou :none (conta sem foto,
  privacidade, ou erro na API — pra quem chama dá no mesmo: segue sem foto).
  """
  def get_user_profile_photo(user_id) when is_integer(user_id) do
    case post("/getUserProfilePhotos", %{user_id: user_id, limit: 1}) do
      {:ok,
       %{status: 200, body: %{"ok" => true, "result" => %{"photos" => [[_ | _] = sizes | _]}}}} ->
        {:ok, List.last(sizes)["file_id"]}

      _ ->
        :none
    end
  end

  @doc "Envia a animação nativa de dado/dardo/caça-níquel etc."
  def send_dice(chat_id, emoji) do
    post("/sendDice", %{chat_id: chat_id, emoji: emoji})
  end

  @doc "Reposta um GIF pelo file_id, opcionalmente com legenda e reply"
  def send_animation(%{chat_id: chat_id, animation: file_id} = params) do
    body =
      %{chat_id: chat_id, animation: file_id}
      |> maybe_put(:caption, params[:caption])
      |> maybe_put(:parse_mode, params[:parse_mode])
      |> maybe_put(:reply_to_message_id, params[:reply_to_message_id])

    post("/sendAnimation", body)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Apaga o menu de comandos registrado no Telegram. Os comandos do bot são
  deliberadamente não-anunciados: nada de autocomplete pro grupo.
  """
  def delete_my_commands do
    post("/deleteMyCommands", %{})
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

    case GptTalkerbot.RuntimeEnvs.get_telegram_webhook_secret() do
      "" ->
        get("/setWebhook?url=#{server}/webhook&drop_pending_updates=true")

      secret ->
        get("/setWebhook?url=#{server}/webhook&drop_pending_updates=true&secret_token=#{secret}")
    end
  end

  def get_webhook_info() do
    get("/getWebhookInfo")
  end

  defp telegram_api_key, do: Application.get_env(:gpt_talkerbot, :telegram_api_key, "")
end
