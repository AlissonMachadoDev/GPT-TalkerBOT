defmodule GptTalkerbotWeb.Plugs.TelegramAllowed do
  @moduledoc """
  Barreira de acesso do webhook: update de chat/usuário fora das listas
  (allowed_groups, allowed_users) e que não seja do owner é descartado com
  204 antes de chegar ao controller — nada é processado, gravado nem gera
  chamada de LLM.

  Sem essa barreira o bot fica mudo em grupos não autorizados, mas coleta
  as mensagens, cataloga os membros e paga extração de contexto sobre
  conversas que ele nem deveria ler.

  Quem passa carrega a identidade extraída em `conn.assigns` — :chat_id,
  :from_id, :from (o mapa cru) e :owner? — para o controller não repetir
  pattern matching profundo no payload em cada clause.
  """

  import Plug.Conn

  require Logger

  alias GptTalkerbot.RuntimeEnvs

  def init(opts), do: opts

  def call(%Plug.Conn{params: %{"message" => message}} = conn, _opts) do
    chat_id = get_in(message, ["chat", "id"])
    from = message["from"]
    from_id = from && from["id"]
    owner? = owner?(from_id)

    if allowed?(from_id, chat_id, owner?) do
      conn
      |> assign(:chat_id, chat_id)
      |> assign(:from_id, from_id)
      |> assign(:from, from)
      |> assign(:owner?, owner?)
    else
      Logger.info("TelegramAllowed: discarding update from chat #{inspect(chat_id)}")

      conn
      |> send_resp(204, "")
      |> halt()
    end
  end

  # Updates sem "message" (edited_message, reaction...) já caem no
  # catch-all 204 do controller; seguem o caminho de hoje
  def call(conn, _opts), do: assign(conn, :owner?, false)

  # Fail closed: se as listas vierem vazias (ex.: falha no fetch do SSM),
  # o bot fica fechado em vez de aberto para o mundo. O owner passa de
  # qualquer chat: os comandos administrativos chegam pelo privado dele
  defp allowed?(from_id, chat_id, owner?) do
    owner? or
      from_id in RuntimeEnvs.get_allowed_users() or
      chat_id in RuntimeEnvs.get_allowed_groups()
  end

  defp owner?(from_id), do: to_string(from_id) == RuntimeEnvs.get_owner_id()
end
