defmodule GptTalkerbot.Memory.FactExtractor do
  alias GptTalkerbot.LLM
  alias GptTalkerbot.Memory

  @system_prompt """
  Analise a mensagem e extraia fatos relevantes e duráveis sobre o usuário \
  (nome preferido, localização, profissão, gostos, preferências, contexto pessoal).
  A mensagem vem de um grupo de zoeira: ignore ironia, sarcasmo, piadas, \
  hipérboles e conteúdo sexual de brincadeira — extraia apenas fatos literais \
  que a pessoa afirma seriamente sobre si mesma. Na dúvida, não extraia.
  Responda APENAS com JSON no formato: [{"key": "nome", "value": "João"}]
  Se não houver fatos relevantes, responda com: []
  Não inclua nada além do JSON.
  """

  # Mensagens muito curtas ("kkkk", "sim") raramente contêm fatos duráveis —
  # pular a extração evita uma chamada de API por mensagem
  @min_text_length 25

  def extract_and_save(user_id, text) when is_binary(text) do
    if String.length(text) >= @min_text_length do
      Task.start(fn -> extract(user_id, text) end)
    else
      :ok
    end
  end

  def extract_and_save(_user_id, _text), do: :ok

  defp extract(user_id, text) do
    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: text}
    ]

    with {:ok, content} <-
           LLM.complete_text(messages,
             user: user_id,
             temperature: 0.2,
             max_tokens: 200,
             reasoning_effort: "none"
           ),
         {:ok, facts} when is_list(facts) <- Jason.decode(String.trim(content)) do
      Enum.each(facts, fn
        %{"key" => key, "value" => value} -> Memory.upsert_fact(user_id, key, value)
        _ -> :ok
      end)
    else
      _ -> :ok
    end
  end
end
