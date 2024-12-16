defmodule GptTalkerbot.CommandsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `GptTalkerbot.Commands` context.
  """

  @doc """
  Generate a command.
  """
  def command_fixture(attrs \\ %{}) do
    {:ok, command} =
      attrs
      |> Enum.into(%{
        content: "some content",
        enabled: true,
        key: "some key",
        user_id: "some user_id"
      })
      |> GptTalkerbot.Commands.create_command()

    command
  end
end
