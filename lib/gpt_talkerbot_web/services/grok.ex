defmodule GptTalkerbotWeb.Services.Grok do
  use Tesla
  defp default_prompt, do: Application.get_env(:gpt_talkerbot, :default_prompt, "")

  @doc """
  Creates a client to make the OpenAI requests.
  """
  def new(api_key) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.x.ai/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, log_level: :warn}
    ]

    Tesla.client(middleware)
  end

  @doc """
    Creates a grok completion, sending user messages to get a text based on it.
  """
  def grok_completion(client, user, messages, settings \\ default_settings()) do
    final_messages = build_messages(settings[:prompt], messages)

    Tesla.post(client, "/chat/completions", %{
      "model" => "grok-4-fast-non-reasoning",
      "messages" => final_messages,
      "temperature" => settings[:temperature],
      "top_p" => settings[:top_p],
      "max_tokens" => 2300,
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

  defp default_settings() do
    %{
      prompt: default_prompt(),
      temperature: 1.5,
      top_p: 0.9,
      max_completion_tokens: 2300
    }
  end
end
