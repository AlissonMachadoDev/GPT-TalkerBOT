defmodule GptTalkerbotWeb.Services.OpenAI do
  use Tesla
  @default_prompt Application.get_env(:gpt_talkerbot, :default_prompt)

  @doc """
  Creates a client to make the OpenAI requests.
  """
  def new(api_key) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, log_level: :warn}
    ]

    Tesla.client(middleware)
  end

  @doc """
    Creates a gpt completion, sending user messages to get a text based on it.
  """
  def gpt_completion(client, text, user, settings \\ default_settings()) do
    Tesla.post(client, "/chat/completions", %{
      "model" => "chatgpt-4o-latest",
      "messages" => build_messages(settings[:prompt], text),
      "temperature" => settings[:temperature],
      "top_p" => settings[:top_p],
      "frequency_penalty" => settings[:frequency_penalty],
      "presence_penalty" => settings[:presence_penalty],
      "max_tokens" => 2300,
      "user" => user
    })
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}
  defp handle_response(_), do: {:error, "Erro ao chamar GPT"}

  defp build_messages(prompt, text) when prompt in [nil, ""] do
    [%{role: "user", content: text}]
  end

  defp build_messages(prompt, text) do
    [%{role: "system", content: prompt}, %{role: "user", content: text}]
  end

  defp default_settings() do
    %{
      prompt: default_prompt(),
      temperature: 1.5,
      top_p: 0.9,
      frequency_penalty: 0.2,
      presence_penalty: 0.4,
      max_tokens: 2300
    }
  end

  defp default_prompt() do
    @default_prompt
  end
end
