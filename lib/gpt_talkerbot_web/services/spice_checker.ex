defmodule GptTalkerbotWeb.Services.SpiceChecker do
  use Tesla

  require Logger
  alias GptTalkerbot.RuntimeEnvs.GenServer, as: RuntimeEnvs

  def threshold, do: RuntimeEnvs.get_spice_threshold()

  def new(api_key) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.openai.com/v1"},
      {Tesla.Middleware.BearerAuth, token: api_key},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Logger, level: :warning}
    ]

    Tesla.client(middleware)
  end

  @doc """
  Returns {:ok, score} where score is a float 0.0–1.0 representing the
  highest category score from OpenAI's moderation endpoint.
  Returns {:error, :unavailable} if the request fails.
  """
  def score(text) when is_binary(text) do
    client = RuntimeEnvs.get_openai_api_key() |> new()

    case Tesla.post(client, "/moderations", %{"input" => text}) do
      {:ok, %{status: 200, body: body}} ->
        Logger.info("SpiceChecker score response: #{inspect(body)}")
        {:ok, extract_score(body)}

      _ ->
        Logger.warning("SpiceChecker score request failed")
        {:error, :unavailable}
    end
  end

  def score(_), do: {:ok, 0.0}

  @doc """
  Returns the service to use (:grok or :openai) based on spice score.
  Falls back to the current RuntimeEnvs service if the check fails.
  """
  def route(text) do
    case score(text) do
      {:ok, s} -> if s > threshold(), do: :grok, else: :openai
      {:error, _} -> RuntimeEnvs.get_current_service()
    end
  end

  defp extract_score(body) do
    body
    |> get_in(["results", Access.at(0), "category_scores"])
    |> case do
      nil -> 0.0
      scores -> scores |> Map.values() |> Enum.max()
    end
  end
end
