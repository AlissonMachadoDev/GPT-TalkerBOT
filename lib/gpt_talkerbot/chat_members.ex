defmodule GptTalkerbot.ChatMembers do
  @moduledoc """
  Registro de membros conhecidos por chat.

  A Bot API do Telegram não tem método para listar todos os membros de um
  grupo, então a lista é construída por observação: quem manda mensagem é
  registrado, service messages de entrada/saída atualizam o status, e os
  administradores (única listagem que a API oferece) semeiam o registro na
  primeira vez que o chat aparece.
  """

  import Ecto.Query

  require Logger

  alias GptTalkerbot.Repo
  alias GptTalkerbot.ChatMembers.{Cache, ChatMember}
  alias GptTalkerbotWeb.Services.Telegram

  @max_listed 30

  @doc """
  Registra/atualiza um membro a partir do "from" cru do update, em background.
  Na primeira vez que o chat aparece, semeia o registro com os admins.
  """
  def track_async(chat_id, %{"id" => _} = user) do
    Task.start(fn ->
      maybe_seed_admins(chat_id)
      track(chat_id, user)
    end)

    :ok
  end

  def track_async(_chat_id, _user), do: :ok

  def track(chat_id, %{"id" => id} = user) do
    if user["is_bot"] do
      :ok
    else
      put_member(chat_id, id, user["first_name"], user["username"], "active")
    end
  end

  def track(_chat_id, _user), do: :ok

  def mark_left(chat_id, %{"id" => id} = user) do
    put_member(chat_id, id, user["first_name"], user["username"], "left")
  end

  def mark_left(_chat_id, _user), do: :ok

  @doc "Membros ativos do chat, em ordem alfabética"
  def list_members(chat_id, limit \\ @max_listed) do
    ChatMember
    |> where([m], m.chat_id == ^to_string(chat_id) and m.status == "active")
    |> order_by([m], asc: m.first_name)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Nomes dos membros ativos, para injetar em prompts"
  def list_names(chat_id, limit \\ @max_listed) do
    list_members(chat_id, limit)
    |> Enum.map(& &1.first_name)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Bloco pronto para system prompt: quem está no chat + como mencionar
  com notificação. Retorna "" se o chat ainda não tem membros conhecidos.
  """
  def prompt_section(chat_id) do
    case list_members(chat_id) do
      [] ->
        ""

      members ->
        lista = Enum.map_join(members, ", ", &"#{&1.first_name} (id #{&1.user_id})")

        "\n\nPessoas deste chat: " <>
          lista <>
          "\nPara mencionar alguém notificando a pessoa, escreva exatamente " <>
          ~s(<a href="tg://user?id=ID">Nome</a> com o id da lista. Use com moderação — ) <>
          "só quando a piada pedir a pessoa específica."
    end
  end

  @doc "Semeia o registro com os administradores do chat (única listagem da API)"
  def seed_admins(chat_id) do
    case Telegram.get_chat_administrators(chat_id) do
      {:ok, admins} ->
        Enum.each(admins, fn %{"user" => user} -> track(chat_id, user) end)

      {:error, reason} ->
        Logger.warning("ChatMembers: failed to fetch administrators for #{chat_id}: #{inspect(reason)}")
    end
  end

  defp maybe_seed_admins(chat_id) do
    key = {:seeded, to_string(chat_id)}

    unless Cache.get(key) do
      exists? =
        ChatMember
        |> where([m], m.chat_id == ^to_string(chat_id))
        |> Repo.exists?()

      unless exists?, do: seed_admins(chat_id)
      Cache.put(key, true)
    end
  end

  # Só toca o banco quando o registro mudou — a tabela é um cadastro de
  # membros, não um rastro de atividade
  defp put_member(chat_id, user_id, first_name, username, status) do
    key = {:member, to_string(chat_id), to_string(user_id)}
    data = {first_name, username, status}

    if Cache.get(key) == data do
      :ok
    else
      case upsert(chat_id, user_id, first_name, username, status) do
        {:ok, _} -> Cache.put(key, data)
        error -> error
      end
    end
  end

  defp upsert(chat_id, user_id, first_name, username, status) do
    %ChatMember{}
    |> ChatMember.changeset(%{
      chat_id: to_string(chat_id),
      user_id: to_string(user_id),
      first_name: first_name,
      username: username,
      status: status
    })
    |> Repo.insert(
      on_conflict: [
        set: [first_name: first_name, username: username, status: status, updated_at: DateTime.utc_now()]
      ],
      conflict_target: [:chat_id, :user_id]
    )
  end
end
