defmodule GptTalkerbot.Warns do
  @moduledoc """
  Contador de warns por usuário e chat, para o /ratowarn.

  Nenhuma punição real: ao atingir o limite o rato perdoa, zera o contador
  e a pessoa ganha mais uma chance.
  """

  import Ecto.Query

  alias GptTalkerbot.Repo
  alias GptTalkerbot.Warns.UserWarn

  @limit 6

  def limit, do: @limit

  @doc "Incrementa e retorna o total de warns do usuário no chat"
  def increment(chat_id, user_id, first_name) do
    {:ok, warn} =
      %UserWarn{}
      |> UserWarn.changeset(%{
        chat_id: to_string(chat_id),
        user_id: to_string(user_id),
        first_name: first_name,
        count: 1
      })
      |> Repo.insert(
        on_conflict: [
          inc: [count: 1],
          set: [first_name: first_name, updated_at: DateTime.utc_now()]
        ],
        conflict_target: [:chat_id, :user_id],
        returning: [:count]
      )

    warn.count
  end

  @doc "Zera o contador (o perdão do rato)"
  def reset(chat_id, user_id) do
    UserWarn
    |> where([w], w.chat_id == ^to_string(chat_id) and w.user_id == ^to_string(user_id))
    |> Repo.update_all(set: [count: 0, updated_at: DateTime.utc_now()])

    :ok
  end
end
