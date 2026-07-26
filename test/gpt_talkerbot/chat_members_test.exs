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

    test "track_activity marca a hora da última mensagem" do
      ChatMembers.track_activity(@chat_id, user(111, "Marcela"))

      last = Repo.get_by(ChatMember, chat_id: @chat_id, user_id: "111").last_message_at

      assert DateTime.diff(DateTime.utc_now(), last) <= 5
    end

    test "membro só cadastrado, sem mensagem, não tem marca de atividade" do
      ChatMembers.track(@chat_id, user(111, "Marcela"))

      assert Repo.get_by(ChatMember, chat_id: @chat_id, user_id: "111").last_message_at == nil
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

    test "tagarela dominante não expulsa o resto do páreo" do
      ChatMembers.track(@chat_id, user(1, "Tagarela"))
      ChatMembers.track(@chat_id, user(2, "Quieta"))
      set_count("1", 2000)
      set_count("2", 6)

      names = ChatMembers.list_frequent_members(@chat_id) |> Enum.map(& &1.first_name)

      assert Enum.sort(names) == ["Quieta", "Tagarela"]
    end

    test "list_frequent_members fica só com os 8 mais falantes" do
      for i <- 1..10 do
        ChatMembers.track(@chat_id, user(i, "Membro#{i}"))
        set_count(to_string(i), i * 10)
      end

      names = ChatMembers.list_frequent_members(@chat_id) |> Enum.map(& &1.first_name)

      assert names == Enum.map(10..3//-1, &"Membro#{&1}")
    end

    test "membro que saiu do grupo não entra no páreo" do
      ChatMembers.track(@chat_id, user(1, "Presente"))
      ChatMembers.track(@chat_id, user(2, "Exilada"))
      set_count("1", 10)
      set_count("2", 500)
      ChatMembers.mark_left(@chat_id, user(2, "Exilada"))

      names = ChatMembers.list_frequent_members(@chat_id) |> Enum.map(& &1.first_name)

      assert names == ["Presente"]
    end

    test "chat sem contadores não tem frequentes" do
      ChatMembers.track(@chat_id, user(1, "Nova"))

      assert ChatMembers.list_frequent_members(@chat_id) == []
    end

    test "quem falou muito e sumiu sai do páreo" do
      ChatMembers.track(@chat_id, user(1, "Presente"))
      ChatMembers.track(@chat_id, user(2, "Fantasma"))
      set_count("1", 10, 3)
      set_count("2", 900, 45)

      names = ChatMembers.list_frequent_members(@chat_id) |> Enum.map(& &1.first_name)

      assert names == ["Presente"]
    end

    test "quem voltou a falar dentro da janela continua no páreo" do
      ChatMembers.track(@chat_id, user(1, "Sazonal"))
      set_count("1", 50, 29)

      names = ChatMembers.list_frequent_members(@chat_id) |> Enum.map(& &1.first_name)

      assert names == ["Sazonal"]
    end
  end

  describe "list_ranked_members/2" do
    test "frequentes vêm antes dos demais, independente do alfabeto" do
      ChatMembers.track(@chat_id, user(1, "Zeca"))
      ChatMembers.track(@chat_id, user(2, "Ana"))
      set_count("1", 80)
      set_count("2", 1)

      names = ChatMembers.list_ranked_members(@chat_id) |> Enum.map(& &1.first_name)

      assert names == ["Zeca", "Ana"]
    end

    test "sem frequentes suficientes, completa com os mais falantes" do
      ChatMembers.track(@chat_id, user(1, "Tagarela"))
      ChatMembers.track(@chat_id, user(2, "Media"))
      ChatMembers.track(@chat_id, user(3, "Muda"))
      set_count("1", 30)
      set_count("2", 3)
      set_count("3", 1)

      names = ChatMembers.list_ranked_members(@chat_id, 2) |> Enum.map(& &1.first_name)

      assert names == ["Tagarela", "Media"]
    end

    test "membro sem nenhuma atividade fica atrás de quem já falou" do
      ChatMembers.track(@chat_id, user(1, "Nunca"))
      ChatMembers.track(@chat_id, user(2, "UmaVez"))
      set_count("2", 1)

      names = ChatMembers.list_ranked_members(@chat_id) |> Enum.map(& &1.first_name)

      assert names == ["UmaVez", "Nunca"]
    end

    test "quem saiu do grupo não aparece" do
      ChatMembers.track(@chat_id, user(1, "Presente"))
      ChatMembers.track(@chat_id, user(2, "Exilada"))
      set_count("2", 500)
      ChatMembers.mark_left(@chat_id, user(2, "Exilada"))

      names = ChatMembers.list_ranked_members(@chat_id) |> Enum.map(& &1.first_name)

      assert names == ["Presente"]
    end
  end

  describe "prompt_section/1" do
    test "chat sem membros conhecidos não gera bloco" do
      assert ChatMembers.prompt_section(@chat_id) == ""
    end

    test "separa quem participa de quem só consta" do
      ChatMembers.track(@chat_id, user(1, "Tagarela"))
      ChatMembers.track(@chat_id, user(2, "Lurker"))
      set_count("1", 40)

      section = ChatMembers.prompt_section(@chat_id)
      [pickable, reference] = String.split(section, "Também estão no grupo")

      assert pickable =~ "Tagarela (id 1)"
      refute pickable =~ "Lurker"
      assert reference =~ "Lurker (id 2)"
    end

    test "sem frequentes, todo mundo é sorteável e não há lista de referência" do
      ChatMembers.track(@chat_id, user(1, "Nova"))

      section = ChatMembers.prompt_section(@chat_id)

      assert section =~ "Nova (id 1)"
      refute section =~ "Também estão no grupo"
    end

    test "admin semeado que nunca falou não entra no sorteio" do
      ChatMembers.track(@chat_id, user(1, "Faladora"))
      ChatMembers.track(@chat_id, user(2, "AdminMudo"))
      set_count("1", 40)

      [pickable, _reference] =
        @chat_id |> ChatMembers.prompt_section() |> String.split("Também estão no grupo")

      refute pickable =~ "AdminMudo"
    end
  end

  # days_ago simula quem falou muito mas sumiu — o contador é vitalício, é a
  # marca da última mensagem que tira essa pessoa do páreo
  defp set_count(user_id, count, days_ago \\ 0) do
    last = DateTime.utc_now() |> DateTime.add(-days_ago, :day) |> DateTime.truncate(:second)

    Repo.get_by(ChatMember, chat_id: @chat_id, user_id: user_id)
    |> Ecto.Changeset.change(message_count: count, last_message_at: last)
    |> Repo.update!()
  end
end
