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

  Todo call site é uma mensagem real chegando, então também conta a
  atividade — é o que alimenta list_frequent_members/2.
  """
  def track_async(chat_id, %{"id" => _} = user) do
    Task.start(fn ->
      maybe_seed_admins(chat_id)
      track_activity(chat_id, user)
    end)

    :ok
  end

  def track_async(_chat_id, _user), do: :ok

  @doc "Registra o membro, incrementa o contador dele e marca a hora da mensagem"
  def track_activity(chat_id, %{"id" => id} = user) do
    track(chat_id, user)

    unless user["is_bot"] do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      ChatMember
      |> where([m], m.chat_id == ^to_string(chat_id) and m.user_id == ^to_string(id))
      |> Repo.update_all(inc: [message_count: 1], set: [last_message_at: now])
    end

    :ok
  end

  def track_activity(_chat_id, _user), do: :ok

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

  @doc """
  Membros ativos do chat, em ordem alfabética. Use `:all` como limite para
  busca por nome — com o corte, quem tem nome no fim do alfabeto some da
  consulta e vira "não conheço essa pessoa".
  """
  def list_members(chat_id, limit \\ @max_listed) do
    ChatMember
    |> where([m], m.chat_id == ^to_string(chat_id) and m.status == "active")
    |> order_by([m], asc: m.first_name)
    |> apply_limit(limit)
    |> Repo.all()
  end

  defp apply_limit(query, :all), do: query
  defp apply_limit(query, count), do: limit(query, ^count)

  @doc "Primeiro nome do membro neste chat, ou nil se ainda desconhecido"
  def get_first_name(chat_id, user_id) do
    ChatMember
    |> where([m], m.chat_id == ^to_string(chat_id) and m.user_id == ^to_string(user_id))
    |> select([m], m.first_name)
    |> Repo.one()
  end

  @doc "Nomes dos membros ativos, para injetar em prompts"
  def list_names(chat_id, limit \\ @max_listed) do
    list_members(chat_id, limit)
    |> Enum.map(& &1.first_name)
    |> Enum.reject(&is_nil/1)
  end

  # Frequente = está entre os @top_talkers mais falantes do chat, tendo
  # falado pelo menos @min_messages vezes e aparecido nos últimos
  # @window_days dias. O contador é vitalício, então sem a janela quem
  # falou muito e sumiu continuaria "frequente" para sempre.
  @min_messages 5
  @top_talkers 8
  @window_days 30

  @doc """
  Os membros ativos mais falantes do chat. Todos entram com peso igual —
  quem chama sorteia uniformemente; a frequência só decide quem está no
  páreo, não quantas vezes aparece.
  """
  def list_frequent_members(chat_id, limit \\ @top_talkers) do
    cutoff = DateTime.add(DateTime.utc_now(), -@window_days, :day)

    ChatMember
    |> where([m], m.chat_id == ^to_string(chat_id) and m.status == "active")
    |> where([m], m.message_count >= @min_messages)
    |> where([m], m.last_message_at >= ^cutoff)
    |> order_by([m], desc: m.message_count, asc: m.first_name)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Membros ordenados por participação: os frequentes primeiro e, se sobrar
  vaga até `limit`, os mais falantes entre os demais.

  É o que vai para prompt e para enquete. A lista alfabética não serve aqui
  porque o corte cai em quem tem nome no começo do alfabeto — critério sem
  nenhuma relação com participar do grupo.
  """
  def list_ranked_members(chat_id, limit \\ @max_listed) do
    frequent = list_frequent_members(chat_id, limit)

    frequent ++ list_others(chat_id, frequent, limit - length(frequent))
  end

  defp list_others(_chat_id, _frequent, remaining) when remaining <= 0, do: []

  defp list_others(chat_id, frequent, remaining) do
    excluded = Enum.map(frequent, & &1.id)

    ChatMember
    |> where([m], m.chat_id == ^to_string(chat_id) and m.status == "active")
    |> where([m], m.id not in ^excluded)
    |> order_by([m],
      desc: m.message_count,
      desc_nulls_last: m.last_message_at,
      asc: m.first_name
    )
    |> limit(^remaining)
    |> Repo.all()
  end

  @doc """
  Bloco pronto para system prompt: quem está no chat + como mencionar
  com notificação. Retorna "" se o chat ainda não tem membros conhecidos.

  Separa quem participa de quem só consta: sem essa divisão o modelo
  sorteia e cutuca gente que nunca abriu a boca no grupo — inclusive os
  admins que o `seed_admins/1` cadastrou sem nunca terem falado.
  """
  def prompt_section(chat_id) do
    frequent = list_frequent_members(chat_id, @max_listed)
    others = list_others(chat_id, frequent, @max_listed - length(frequent))

    case {frequent, others} do
      {[], []} -> ""
      {[], others} -> section(others, [])
      {frequent, others} -> section(frequent, others)
    end
  end

  defp section(pickable, reference) do
    "\n\nPessoas deste chat que participam das conversas — escolha, sorteie ou " <>
      "mencione SOMENTE alguém desta lista: " <>
      format_members(pickable) <>
      reference_line(reference) <>
      "\nPara mencionar alguém notificando a pessoa, escreva exatamente " <>
      ~s(<a href="tg://user?id=ID">Nome</a> com o id da lista. Use com moderação — ) <>
      "só quando a piada pedir a pessoa específica."
  end

  defp reference_line([]), do: ""

  defp reference_line(members) do
    "\nTambém estão no grupo, mas quase não falam — só para você reconhecer o " <>
      "nome se alguém citar, nunca para sortear ou mencionar por conta própria: " <>
      format_members(members)
  end

  defp format_members(members) do
    Enum.map_join(members, ", ", &"#{&1.first_name} (id #{&1.user_id})")
  end

  @doc "Semeia o registro com os administradores do chat (única listagem da API)"
  def seed_admins(chat_id) do
    case Telegram.get_chat_administrators(chat_id) do
      {:ok, admins} ->
        Enum.each(admins, fn %{"user" => user} -> track(chat_id, user) end)

      {:error, reason} ->
        Logger.warning(
          "ChatMembers: failed to fetch administrators for #{chat_id}: #{inspect(reason)}"
        )
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
        set: [
          first_name: first_name,
          username: username,
          status: status,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: [:chat_id, :user_id]
    )
  end
end
