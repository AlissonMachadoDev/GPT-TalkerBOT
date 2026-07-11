defmodule GptTalkerbot.ChatMembersTest do
  use GptTalkerbot.DataCase

  alias GptTalkerbot.ChatMembers
  alias GptTalkerbot.ChatMembers.{Cache, ChatMember}

  @chat_id "-100777"

  setup do
    Cache.reset()
    :ok
  end

  defp user(id, name, username \\ nil) do
    %{"id" => id, "first_name" => name, "username" => username, "is_bot" => false}
  end

  test "mensagem repetida do mesmo membro não reescreve no banco" do
    ChatMembers.track(@chat_id, user(111, "Marcela"))
    original = Repo.get_by(ChatMember, chat_id: @chat_id, user_id: "111")

    ChatMembers.track(@chat_id, user(111, "Marcela"))
    unchanged = Repo.get_by(ChatMember, chat_id: @chat_id, user_id: "111")

    assert unchanged.updated_at == original.updated_at
  end

  test "mudança de nome atualiza o registro" do
    ChatMembers.track(@chat_id, user(111, "Marcela"))
    ChatMembers.track(@chat_id, user(111, "Marcela Silva"))

    assert Repo.get_by(ChatMember, chat_id: @chat_id, user_id: "111").first_name ==
             "Marcela Silva"
  end

  test "saída e volta ao grupo atualizam o status" do
    ChatMembers.track(@chat_id, user(111, "Marcela"))
    ChatMembers.mark_left(@chat_id, user(111, "Marcela"))

    assert ChatMembers.list_members(@chat_id) == []

    ChatMembers.track(@chat_id, user(111, "Marcela"))
    assert [%{status: "active"}] = ChatMembers.list_members(@chat_id)
  end

  test "bots não são registrados" do
    ChatMembers.track(@chat_id, %{"id" => 999, "first_name" => "Ratobô", "is_bot" => true})
    assert ChatMembers.list_members(@chat_id) == []
  end

  test "lista sai em ordem alfabética" do
    ChatMembers.track(@chat_id, user(111, "Zeca"))
    ChatMembers.track(@chat_id, user(222, "Ana"))
    ChatMembers.track(@chat_id, user(333, "Beto"))

    assert ChatMembers.list_names(@chat_id) == ["Ana", "Beto", "Zeca"]
  end
end
