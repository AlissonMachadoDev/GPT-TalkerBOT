defmodule GptTalkerbotWeb.Services.Embeddings do
  use Tesla

  alias GptTalkerbot.RuntimeEnvs

  @model "text-embedding-3-small"

  def embed_batch(texts) when is_list(texts) do
    client = RuntimeEnvs.get_openai_api_key() |> new()

    case Tesla.post(client, "/embeddings", %{"model" => @model, "input" => texts}) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        embeddings =
          data
          |> Enum.sort_by(& &1["index"])
          |> Enum.map(& &1["embedding"])

        {:ok, embeddings}

      _ ->
        {:error, :unavailable}
    end
  end

  defp new(api_key) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, level: :warning}
    ]

    Tesla.client(middleware)
  end
end
