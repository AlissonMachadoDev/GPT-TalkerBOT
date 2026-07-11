defmodule GptTalkerbotWeb.Services.Grok do
  use Tesla

  def new(api_key) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.x.ai/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, level: :warning}
    ]

    Tesla.client(middleware)
  end

  def grok_completion(client, user, messages, settings) do
    final_messages = build_messages(settings[:prompt], messages)

    body =
      %{
        "model" => settings[:model] || "grok-4.3",
        "messages" => final_messages,
        "temperature" => settings[:temperature],
        "reasoning_effort" => settings[:reasoning_effort],
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
  defp handle_response(_), do: {:error, "Erro ao chamar GROK"}

  defp build_messages(prompt, messages) when prompt in [nil, ""], do: messages

  defp build_messages(prompt, messages) do
    [%{role: "system", content: prompt} | messages]
  end
end
