defmodule GptTalkerbot.Memory.FactExtractor do
  alias GptTalkerbotWeb.Services.{OpenAI, Grok}
  alias GptTalkerbot.RuntimeEnvs.GenServer, as: RuntimeEnvs
  alias GptTalkerbot.Memory

  @system_prompt """
  Analise a mensagem e extraia fatos relevantes e duráveis sobre o usuário \
  (nome preferido, localização, profissão, gostos, preferências, contexto pessoal).
  Responda APENAS com JSON no formato: [{"key": "nome", "value": "João"}]
  Se não houver fatos relevantes, responda com: []
  Não inclua nada além do JSON.
  """

  @openai_settings %{
    prompt: nil,
    temperature: 0.2,
    frequency_penalty: 0.0,
    presence_penalty: 0.0,
    max_completion_tokens: 200
  }

  @grok_settings %{
    prompt: nil,
    temperature: 0.2,
    reasoning_effort: "none",
    max_completion_tokens: 200
  }

  def extract_and_save(user_id, text) do
    Task.start(fn ->
      messages = [
        %{role: "system", content: @system_prompt},
        %{role: "user", content: text}
      ]

      with {:ok, body} <- call_ai(user_id, messages),
           content when is_binary(content) <-
             get_in(body, ["choices", Access.at(0), "message", "content"]),
           {:ok, facts} <- Jason.decode(String.trim(content)),
           true <- is_list(facts) do
        Enum.each(facts, fn
          %{"key" => key, "value" => value} -> Memory.upsert_fact(user_id, key, value)
          _ -> :ok
        end)
      else
        _ -> :ok
      end
    end)
  end

  defp call_ai(user_id, messages) do
    case RuntimeEnvs.get_current_service() do
      :openai ->
        RuntimeEnvs.get_openai_api_key()
        |> OpenAI.new()
        |> OpenAI.gpt_completion(user_id, messages, @openai_settings)

      :grok ->
        RuntimeEnvs.get_grok_api_key()
        |> Grok.new()
        |> Grok.grok_completion(user_id, messages, @grok_settings)
    end
  end
end
