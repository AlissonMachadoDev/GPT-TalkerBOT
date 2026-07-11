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
          {:ok, body}
      end
    end
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
