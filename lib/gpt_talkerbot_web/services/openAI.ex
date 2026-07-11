defmodule GptTalkerbotWeb.Services.OpenAI do
  use Tesla

  def new(api_key) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, level: :warning}
    ]

    Tesla.client(middleware)
  end

  def gpt_completion(client, user, messages, settings) do
    final_messages = build_messages(settings[:prompt], messages)

    body =
      %{
        "model" => settings[:model] || "gpt-5.4-mini",
        "messages" => final_messages,
        "temperature" => settings[:temperature],
        "frequency_penalty" => settings[:frequency_penalty],
        "presence_penalty" => settings[:presence_penalty],
        "max_completion_tokens" => settings[:max_completion_tokens],
        "user" => user
      }
      |> maybe_put_tools(settings[:tools])

    Tesla.post(client, "/chat/completions", body)
    |> handle_response()
  end

  defp maybe_put_tools(body, tools) when is_list(tools) and tools != [],
    do: Map.put(body, "tools", tools)

  defp maybe_put_tools(body, _), do: body

  defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}
  defp handle_response(_), do: {:error, "Erro ao chamar GPT"}

  defp build_messages(prompt, messages) when prompt in [nil, ""], do: messages

  defp build_messages(prompt, messages) do
    [%{role: "system", content: prompt} | messages]
  end
end
