defmodule GptTalkerbot.AccessFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `GptTalkerbot.Access` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        api_key: "some api_key",
        master_user_id: "some master_user_id",
        telegram_id: "some telegram_id"
      })
      |> GptTalkerbot.Access.create_user()

    user
  end

  @doc """
  Generate a group.
  """
  def group_fixture(attrs \\ %{}) do
    {:ok, group} =
      attrs
      |> Enum.into(%{
        telegram_id: "some telegram_id",
        user_id: "some user_id"
      })
      |> GptTalkerbot.Access.create_group()

    group
  end
end
