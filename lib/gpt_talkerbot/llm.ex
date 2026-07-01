defmodule GptTalkerbot.LLM do
  @moduledoc """
  Ponto único de acesso aos provedores de LLM (OpenAI e Grok).

  Centraliza a escolha de provider, chaves, modelos e defaults de settings,
  eliminando o case :openai/:grok que se repetia em cada caller.

  Opções:
    * :provider - :openai, :grok ou :auto (usa RuntimeEnvs.get_current_service/0)
    * :prompt - system prompt
    * :user - identificador do usuário repassado à API
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
      max_completion_tokens: Keyword.get(opts, :max_tokens, 1000)
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

  @doc """
  Como complete/2, mas já extrai o texto da primeira choice.
  """
  def complete_text(messages, opts \\ []) do
    with {:ok, body} <- complete(messages, opts),
         content when is_binary(content) <-
           get_in(body, ["choices", Access.at(0), "message", "content"]) do
      {:ok, content}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :empty_response}
    end
  end

  defp resolve_provider(:auto), do: RuntimeEnvs.get_current_service()
  defp resolve_provider(provider) when provider in [:openai, :grok], do: provider
end
