defmodule GptTalkerbotWeb.DataFormat do
  def init(opts), do: opts

  def call(%Plug.Conn{params: params} = conn, _opts) do
    converted_params = convert_ids(params)
    %{conn | params: converted_params}
  end

  defp convert_ids(%{"message" => message} = params) when is_map(message) do
    %{params | "message" => convert_message_ids(message)}
  end

  defp convert_ids(params), do: params

  defp convert_message_ids(message) do
    message
    |> convert_chat_id()
    |> convert_user_id()
  end

  defp convert_chat_id(%{"chat" => %{"id" => id}} = message) when is_integer(id) do
    put_in(message, ["chat", "id"], Integer.to_string(id))
  end

  defp convert_chat_id(message), do: message

  defp convert_user_id(%{"from" => %{"id" => id}} = message) when is_integer(id) do
    put_in(message, ["from", "id"], Integer.to_string(id))
  end

  defp convert_user_id(message), do: message
end
