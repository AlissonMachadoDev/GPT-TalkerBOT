defmodule GptTalkerbot.WarnsTest do
  use GptTalkerbot.DataCase

  alias GptTalkerbot.Warns
  alias GptTalkerbot.Warns.WarnEntry

  @chat_id "-100555"

  describe "record_entry/1" do
    test "grava o dossiê completo do warn" do
      {:ok, entry} =
        Warns.record_entry(%{
          chat_id: @chat_id,
          user_id: "111",
          first_name: "Beto",
          issuer_name: "Alisson",
          offending_message: "pineapple na pizza é bom",
          request_message: "/ratowarn",
          bot_response: "⚠️ Warn 1/6 para Beto\n\nViolação do artigo 3 do Regulamento do Esgoto."
        })

      assert entry.offending_message == "pineapple na pizza é bom"
      assert entry.request_message == "/ratowarn"
      assert entry.bot_response =~ "Regulamento"
      assert entry.issuer_name == "Alisson"
      refute entry.forgiven
    end

    test "exige chat_id e user_id" do
      assert {:error, changeset} = Warns.record_entry(%{first_name: "Beto"})
      assert %{chat_id: _, user_id: _} = errors_on(changeset)
    end
  end

  describe "reset/2" do
    test "zera o contador e marca as entradas do usuário como perdoadas" do
      Warns.increment(@chat_id, 111, "Beto")

      {:ok, _} =
        Warns.record_entry(%{chat_id: @chat_id, user_id: "111", offending_message: "spam"})

      {:ok, outro} =
        Warns.record_entry(%{chat_id: @chat_id, user_id: "222", offending_message: "inocente"})

      Warns.reset(@chat_id, 111)

      assert Warns.list_counts(@chat_id) == []
      assert Repo.get_by(WarnEntry, user_id: "111").forgiven
      refute Repo.get(WarnEntry, outro.id).forgiven
    end
  end
end
