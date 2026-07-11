defmodule GptTalkerbot.ChatMembers.Cache do
  @moduledoc """
  Dona da tabela ETS que lembra o que já foi gravado em chat_members.

  Sem ela, cada mensagem do grupo vira um upsert no banco mesmo quando
  nada mudou — a tabela é um cadastro de membros, não rastro de atividade.
  """

  use GenServer

  @table :chat_members_cache

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    {:ok, nil}
  end

  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  def put(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  end

  @doc "Esvazia o cache (usado nos testes, onde o banco é revertido a cada caso)"
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end
end
