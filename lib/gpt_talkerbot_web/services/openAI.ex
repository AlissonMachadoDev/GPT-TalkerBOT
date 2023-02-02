defmodule GptTalkerbotWeb.Services.OpenAI do
  use Tesla

  # defp token, do: Application.get_env(:my_scrobbles_bot, __MODULE__)[:token]

  plug Tesla.Middleware.BaseUrl,
       "https://api.openai.com/v1"

  plug Tesla.Middleware.BearerAuth, token: Application.fetch_env!(:gpt_talkerbot, :openai_api_key)
  plug Tesla.Middleware.Headers
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger, log_level: :warn

  # post("/completions", %{"model" => "text-davinci-003", "prompt" => "Say this is a test", "temperature" => 0, "max_tokens" => 7})

  def test(route, data, query_params \\ []) do
    post(route, data, query_params)
    |> handle_response()
  end

  def ada_completion(text) do
    post("/completions", %{
      "model" => "text-davinci-003",
      "prompt" => text,
      "temperature" => 0.9,
      "max_tokens" => 1900,
      "top_p" => 0.67,
      "frequency_penalty" => 0.5,
      "presence_penalty" => 0
    })
    |> handle_response()
  end

  def get_models() do
    get("/models")
    |> handle_response()
  end

  defp handle_response(response) do
    with {:ok, client} <- response do
      case client.status do
        200 ->
          {:ok, client.body}
      end
    end
  end
end
