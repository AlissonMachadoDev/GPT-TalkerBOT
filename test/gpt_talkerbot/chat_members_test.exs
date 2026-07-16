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

  describe "atividade e frequência" do
    test "track_activity incrementa o contador a cada mensagem" do
      ChatMembers.track_activity(@chat_id, user(111, "Marcela"))
      ChatMembers.track_activity(@chat_id, user(111, "Marcela"))

      assert Repo.get_by(ChatMember, chat_id: @chat_id, user_id: "111").message_count == 2
    end

    test "bot não entra na contagem nem no cadastro" do
      ChatMembers.track_activity(@chat_id, %{
        "id" => 999,
        "first_name" => "OutroBot",
        "is_bot" => true
      })

      assert Repo.get_by(ChatMember, chat_id: @chat_id, user_id: "999") == nil
    end

    test "list_frequent_members corta quem fala pouco" do
      ChatMembers.track(@chat_id, user(1, "Tagarela"))
      ChatMembers.track(@chat_id, user(2, "Mediana"))
      ChatMembers.track(@chat_id, user(3, "Sumida"))
      set_count("1", 100)
      set_count("2", 30)
      set_count("3", 4)

      names = ChatMembers.list_frequent_members(@chat_id) |> Enum.map(& &1.first_name)

      assert Enum.sort(names) == ["Mediana", "Tagarela"]
    end
  end

  describe "filter_frequent/1 (corte puro)" do
    defp member(count), do: %{message_count: count}

    test "corte relativo: pelo menos 25% do mais falante" do
      assert ChatMembers.filter_frequent([member(100), member(25), member(24)]) ==
               [member(100), member(25)]
    end

    test "grupo morno: vale o mínimo absoluto de 5 mensagens" do
      assert ChatMembers.filter_frequent([member(8), member(5), member(4)]) ==
               [member(8), member(5)]
    end

    test "sem contadores ainda, ninguém é frequente" do
      assert ChatMembers.filter_frequent([member(0), member(nil)]) == []
    end

    test "lista vazia não quebra" do
      assert ChatMembers.filter_frequent([]) == []
    end
  end

  defp set_count(user_id, count) do
    Repo.get_by(ChatMember, chat_id: @chat_id, user_id: user_id)
    |> Ecto.Changeset.change(message_count: count)
    |> Repo.update!()
  end
end
