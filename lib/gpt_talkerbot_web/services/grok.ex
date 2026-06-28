defmodule GptTalkerbotWeb.Services.Grok do
  use Tesla

  require Logger

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

    log_final_prompt("Grok", final_messages, settings)

    Tesla.post(client, "/chat/completions", %{
      "model" => "grok-4.3",
      "messages" => final_messages,
      "temperature" => settings[:temperature],
      "reasoning_effort" => settings[:reasoning_effort],
      "max_completion_tokens" => settings[:max_completion_tokens],
      "user" => user
    })
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}
  defp handle_response(_), do: {:error, "Erro ao chamar GROK"}

  defp build_messages(prompt, messages) when prompt in [nil, ""], do: messages

  defp build_messages(prompt, messages) do
    [%{role: "system", content: prompt} | messages]
  end

  defp log_final_prompt(service, messages, settings) do
    total = length(messages)
    system = Enum.find(messages, &(&1.role == "system" || &1[:role] == "system"))
    history = Enum.filter(messages, &(&1.role != "system" && &1[:role] != "system"))

    system_preview = if system do
      content = system.content || system[:content] || ""
      String.slice(content, 0, 200)
    else
      "(none)"
    end

    Logger.info("[#{service}] final prompt: total_messages=#{total} history_messages=#{length(history)} temperature=#{settings[:temperature]} reasoning=#{settings[:reasoning_effort]}")
    Logger.info("[#{service}] system_prompt (first 200 chars): #{system_preview}")

    Enum.with_index(history)
    |> Enum.each(fn {msg, idx} ->
      role = msg.role || msg[:role]
      content = msg.content || msg[:content] || ""
      Logger.info("[#{service}] history[#{idx}] role=#{role} content=\"#{String.slice(content, 0, 120)}\"")
    end)
  end
end
