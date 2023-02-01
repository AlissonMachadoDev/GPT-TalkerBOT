defmodule GptTalkerbot.Events.Event do
  @moduledoc """
  Defines an event which will be consumed by the pipeline.
  """

  @doc """
  Casts the payload
  """
  @callback cast(term) :: {:ok, term()} | {:error, reason :: atom()}
  @callback recast(term) :: {:ok, term()} | {:error, reason :: atom()}
end
