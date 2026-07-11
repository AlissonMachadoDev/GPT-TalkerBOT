defmodule GptTalkerbotWeb.Plugs.TelegramAllowedTest do
  # persistent_term é global: não pode rodar em paralelo com testes que leem RuntimeEnvs
  use ExUnit.Case, async: false

  import Plug.Test

  alias GptTalkerbot.RuntimeEnvs
  alias GptTalkerbotWeb.Plugs.TelegramAllowed

  @allowed_group -1_001
  @allowed_user 777
  @owner_id "42"

  setup do
    previous = :persistent_term.get(RuntimeEnvs, nil)

    :persistent_term.put(RuntimeEnvs, %{
      allowed_groups: [@allowed_group],
      allowed_users: [@allowed_user],
      owner_id: @owner_id
    })

    on_exit(fn ->
      if previous,
        do: :persistent_term.put(RuntimeEnvs, previous),
        else: :persistent_term.erase(RuntimeEnvs)
    end)

    :ok
  end

  defp call_with_message(chat_id, from_id) do
    conn(:post, "/webhook")
    |> Map.put(:params, %{
      "message" => %{
        "text" => "oi",
        "chat" => %{"id" => chat_id},
        "from" => %{"id" => from_id}
      }
    })
    |> TelegramAllowed.call([])
  end

  test "mensagem de grupo permitido passa com a identidade extraída" do
    conn = call_with_message(@allowed_group, 555)

    refute conn.halted
    assert conn.assigns.chat_id == @allowed_group
    assert conn.assigns.from_id == 555
    assert conn.assigns.from == %{"id" => 555}
  end

  test "usuário permitido passa mesmo em chat desconhecido" do
    refute call_with_message(999_888, @allowed_user).halted
  end

  test "owner passa de qualquer chat e chega marcado como owner" do
    conn = call_with_message(424_242, 42)

    refute conn.halted
    assert conn.assigns.owner?
  end

  test "quem não é owner chega com a marca desligada" do
    refute call_with_message(@allowed_group, 555).assigns.owner?
  end

  test "grupo desconhecido é descartado com 204 antes do controller" do
    conn = call_with_message(-999_777, 555)

    assert conn.halted
    assert conn.status == 204
  end

  test "chat privado de estranho é descartado" do
    assert call_with_message(555, 555).halted
  end

  test "update sem message segue para o catch-all do controller" do
    conn =
      conn(:post, "/webhook")
      |> Map.put(:params, %{"edited_message" => %{"chat" => %{"id" => -999_777}}})
      |> TelegramAllowed.call([])

    refute conn.halted
  end
end
