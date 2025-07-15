defmodule GptTalkerbot.ConfigHelpers do
  def parse_env(env) when env in [nil, ""], do: []

  def parse_env(env) do
    env
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&safe_to_integer/1)
    |> Enum.reject(&is_nil/1)
  end

  defp safe_to_integer(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
