defmodule GptTalkerbot.Warns.WarnEntry do
  @moduledoc """
  Dossiê de um warn: a mensagem infratora, o pedido de /ratowarn e a
  resposta do rato. O perdão (reset) marca as entradas como forgiven em
  vez de apagar — a ficha limpa zera o contador, não a memória.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "warn_entries" do
    field :chat_id, :string
    field :user_id, :string
    field :first_name, :string
    field :issuer_name, :string
    field :offending_message, :string
    field :request_message, :string
    field :bot_response, :string
    field :forgiven, :boolean, default: false

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :chat_id,
      :user_id,
      :first_name,
      :issuer_name,
      :offending_message,
      :request_message,
      :bot_response,
      :forgiven
    ])
    |> validate_required([:chat_id, :user_id])
  end
end
