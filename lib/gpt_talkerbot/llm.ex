defmodule GptTalkerbot.LLM do
  @moduledoc """
  Ponto único de acesso aos provedores de LLM (OpenAI e Grok).

  Centraliza a escolha de provider, chaves, modelos e defaults de settings,
  eliminando o case :openai/:grok que se repetia em cada caller.

  Opções:
    * :provider - :openai, :grok ou :auto (usa RuntimeEnvs.get_current_service/0)
    * :prompt - system prompt
    * :user - identificador do usuário repassado à API
    * :tools - specs de tool calling repassadas à API (formato chat completions)
    * :temperature, :max_tokens, :frequency_penalty, :presence_penalty, :reasoning_effort
  """

  alias GptTalkerbot.RuntimeEnvs
  alias GptTalkerbotWeb.Services.{Grok, OpenAI}

  def complete(messages, opts \\ []) do
    provider = resolve_provider(Keyword.get(opts, :provider, :auto))
    user = Keyword.get(opts, :user)

    base = %{
      prompt: Keyword.get(opts, :prompt),
      temperature: Keyword.get(opts, :temperature, RuntimeEnvs.get_temperature()),
      max_completion_tokens: Keyword.get(opts, :max_tokens, 1000),
      tools: Keyword.get(opts, :tools)
    }

    case provider do
      :openai ->
        settings =
          Map.merge(base, %{
            model: RuntimeEnvs.get_openai_model(),
            frequency_penalty: Keyword.get(opts, :frequency_penalty, 0.0),
            presence_penalty: Keyword.get(opts, :presence_penalty, 0.0)
          })

        RuntimeEnvs.get_openai_api_key()
        |> OpenAI.new()
        |> OpenAI.gpt_completion(user, messages, settings)

      :grok ->
        settings =
          Map.merge(base, %{
            model: RuntimeEnvs.get_grok_model(),
            reasoning_effort: Keyword.get(opts, :reasoning_effort, RuntimeEnvs.get_grok_reasoning())
          })

        RuntimeEnvs.get_grok_api_key()
        |> Grok.new()
        |> Grok.grok_completion(user, messages, settings)
    end
  end

  # Duas rodadas bastam: o modelo pode pedir várias tools numa rodada só,
  # e sem limite um tool_call repetido viraria loop infinito de chamadas pagas
  @max_tool_rounds 2

  @doc """
  Como complete/2, mas executa tool calls que o modelo pedir e reenvia os
  resultados até sair uma resposta de texto.

  Requer em opts:
    * :tools - specs das ferramentas
    * :tool_executor - fun (name, arguments_json) -> string com o resultado
  """
  def complete_with_tools(messages, opts) do
    executor = Keyword.fetch!(opts, :tool_executor)
    tool_loop(messages, opts, executor, @max_tool_rounds)
  end

  defp tool_loop(messages, opts, executor, rounds_left) do
    # Esgotadas as rodadas, a última chamada vai sem tools para forçar texto
    call_opts = if rounds_left > 0, do: opts, else: Keyword.delete(opts, :tools)

    with {:ok, body} <- complete(messages, call_opts) do
      message = get_in(body, ["choices", Access.at(0), "message"])

      case message do
        %{"tool_calls" => calls} when is_list(calls) and calls != [] and rounds_left > 0 ->
          results =
            Enum.map(calls, fn call ->
              %{
                role: "tool",
                tool_call_id: call["id"],
                content: executor.(call["function"]["name"], call["function"]["arguments"])
              }
            end)

          # Só role/content/tool_calls voltam para a API: campos extras da
          # resposta (refusal, annotations...) podem ser rejeitados no reenvio
          assistant_msg = Map.take(message, ["role", "content", "tool_calls"])

          tool_loop(messages ++ [assistant_msg | results], opts, executor, rounds_left - 1)

        _ ->
          # Sem tool_calls estruturado. O modelo às vezes *lista os nomes* das
          # ferramentas que queria usar como texto (ex.: "get_group_members\n
          # get_group_context") em vez de chamá-las — e isso vazava como fala
          # do bot. Executa as que ele nomeou e devolve o resultado para ele
          # responder de verdade, agora sem tools (senão repete o vazamento).
          case narrated_tools(message["content"], opts[:tools]) do
            names when names != [] and rounds_left > 0 ->
              tool_loop(messages ++ [narrated_recovery(names, executor)], opts, executor, 0)

            _ ->
              {:ok, body}
          end
      end
    end
  end

  # Mensagem de recuperação: injeta o resultado das ferramentas nomeadas e
  # manda o modelo responder sem citar nomes. Entra como "user" porque não há
  # tool_call_id — a API rejeita role "tool" sem um tool_calls que a preceda.
  defp narrated_recovery(names, executor) do
    resultados = Enum.map_join(names, "\n\n", fn n -> executor.(n, "{}") end)

    %{
      role: "user",
      content:
        "[sistema] Você escreveu nomes de ferramentas em vez de usá-las. Segue o " <>
          "resultado delas — responda a mensagem de verdade, com naturalidade e " <>
          "sem citar nome de ferramenta:\n\n" <> resultados
    }
  end

  @doc false
  # Lista de nomes de ferramentas se o content é composto *só* por nomes
  # conhecidos (um por linha ou separados por vírgula); [] caso contrário,
  # para não disparar quando um nome aparece no meio de uma frase real.
  # Público só para teste — o fluxo usa via tool_loop.
  def narrated_tools(content, tools) when is_binary(content) and is_list(tools) do
    known = tool_names(tools)

    tokens =
      content
      |> String.split(~r/[\n,]+/)
      |> Enum.map(&normalize_tool_token/1)
      |> Enum.reject(&(&1 == ""))

    if tokens != [] and Enum.all?(tokens, &(&1 in known)) do
      Enum.uniq(tokens)
    else
      []
    end
  end

  def narrated_tools(_content, _tools), do: []

  defp normalize_tool_token(token) do
    token
    |> String.trim()
    |> String.trim("`")
    |> String.replace(~r/\(\)\s*$/, "")
    |> String.trim()
  end

  defp tool_names(tools) do
    Enum.map(tools, fn t -> get_in(t, [:function, :name]) || get_in(t, ["function", "name"]) end)
  end

  @doc """
  Como complete/2, mas já extrai o texto da primeira choice.

  Diretivas de pós-ação ([[ratobo:...]]) são removidas: os fluxos que usam
  complete_text (enquetes, warns, resumos...) não executam pós-ações, e um
  marcador vazado viraria texto visível — ou quebraria o tipo da mensagem,
  como um GIF pedido dentro de uma enquete.
  """
  def complete_text(messages, opts \\ []) do
    with {:ok, body} <- complete(messages, opts),
         content when is_binary(content) <-
           get_in(body, ["choices", Access.at(0), "message", "content"]) do
      {:ok, GptTalkerbot.PostActions.strip(content)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :empty_response}
    end
  end

  defp resolve_provider(:auto), do: RuntimeEnvs.get_current_service()
  defp resolve_provider(provider) when provider in [:openai, :grok], do: provider
end
