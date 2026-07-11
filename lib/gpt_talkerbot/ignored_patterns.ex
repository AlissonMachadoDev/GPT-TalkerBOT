defmodule GptTalkerbot.IgnoredPatterns do
  @moduledoc """
  Padrões de texto que tiram mensagens do histórico do bot, por chat
  (comando /ignore_messages).

  Mensagem contendo um padrão não entra no buffer do grupo nem na memória
  de conversa — o bot ainda responde se for chamado, só não registra.

  O GenServer existe apenas para ser dono da tabela ETS: a checagem roda
  em toda mensagem do grupo e não pode custar uma query nem serializar num
  processo. Leituras vão direto na ETS; miss carrega do banco no processo
  chamador.
  """

  use GenServer

  import Ecto.Query

  alias GptTalkerbot.IgnoredPatterns.IgnoredPattern
  alias GptTalkerbot.Repo

  @table :ignored_patterns_cache

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, nil}
  end

  @doc "A mensagem contém algum padrão ignorado deste chat?"
  def ignored?(chat_id, text) when is_binary(text) do
    case patterns(to_string(chat_id)) do
      [] ->
        false

      patterns ->
        haystack = String.downcase(text)
        Enum.any?(patterns, &String.contains?(haystack, &1))
    end
  end

  def ignored?(_chat_id, _text), do: false

  @doc "Registra um padrão para o chat; a comparação é case-insensitive"
  def add(chat_id, pattern) do
    chat_id = to_string(chat_id)
    pattern = pattern |> String.trim() |> String.downcase()

    cond do
      pattern == "" ->
        {:error, :empty}

      pattern in patterns(chat_id) ->
        :already_exists

      true ->
        %IgnoredPattern{}
        |> IgnoredPattern.changeset(%{chat_id: chat_id, pattern: pattern})
        |> Repo.insert(on_conflict: :nothing)
        |> case do
          {:ok, _} ->
            :ets.delete(@table, chat_id)
            :ok

          error ->
            error
        end
    end
  end

  @doc "Padrões ignorados do chat"
  def list(chat_id), do: patterns(to_string(chat_id))

  @doc "Esvazia o cache (usado nos testes, onde o banco é revertido a cada caso)"
  def reset_cache do
    :ets.delete_all_objects(@table)
    :ok
  end

  defp patterns(chat_id) do
    case :ets.lookup(@table, chat_id) do
      [{^chat_id, patterns}] ->
        patterns

      [] ->
        patterns = load_from_db(chat_id)
        :ets.insert(@table, {chat_id, patterns})
        patterns
    end
  end

  defp load_from_db(chat_id) do
    IgnoredPattern
    |> where([p], p.chat_id == ^chat_id)
    |> order_by([p], asc: p.inserted_at)
    |> select([p], p.pattern)
    |> Repo.all()
  end
end
