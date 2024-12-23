defmodule GptTalkerbotWeb.Services.OpenAI do
  use Tesla

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
  def gpt_completion(client, text, user) do
    Tesla.post(client, "/chat/completions", %{
      "model" => "chatgpt-4o-latest",
      "messages" => [%{role: "user", content: text}],
      "temperature" => 0.7,
      "max_tokens" => 2300,
      "user" => user
    })
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}
  defp handle_response(_), do: {:error, "Erro ao chamar GPT"}
end
