defmodule GptTalkerbot.PromptSettings.ContextToolsTest do
  use GptTalkerbot.DataCase

  alias GptTalkerbot.{ChatMembers, Memory, Warns}
  alias GptTalkerbot.PromptSettings.ContextTools

  @chat_id "-100424242"

  # O banco é revertido a cada teste, mas o cache ETS de membros não
  setup do
    ChatMembers.Cache.reset()
    :ok
  end

  defp track(user_id, first_name) do
    ChatMembers.track(@chat_id, %{"id" => user_id, "first_name" => first_name, "is_bot" => false})
  end

  describe "specs/0" do
    test "toda spec tem nome único e formato de function" do
      specs = ContextTools.specs()
      names = Enum.map(specs, & &1.function.name)

      assert Enum.uniq(names) == names
      assert "get_group_members" in names
      assert "get_user_facts" in names
      assert "get_warns" in names
      assert Enum.all?(specs, &(&1.type == "function"))
    end
  end

  describe "get_group_members" do
    test "chat sem membros conhecidos" do
      assert ContextTools.execute("get_group_members", "{}", @chat_id) =~ "Nenhum membro"
    end

    test "lista membros ativos com id para menção" do
      track(111, "Marcela")
      track(222, "Beto")

      result = ContextTools.execute("get_group_members", "{}", @chat_id)

      assert result =~ "Marcela (id 111)"
      assert result =~ "Beto (id 222)"
    end
  end

  describe "get_user_facts" do
    test "resolve nome para membro e devolve fatos" do
      track(111, "Marcela")
      Memory.upsert_fact("111", "profissão", "dentista")

      result = ContextTools.execute("get_user_facts", ~s({"nome": "marcela"}), @chat_id)

      assert result =~ "Marcela"
      assert result =~ "profissão: dentista"
    end

    test "membro conhecido sem fatos" do
      track(222, "Beto")

      assert ContextTools.execute("get_user_facts", ~s({"nome": "Beto"}), @chat_id) =~
               "não sei nada sobre Beto"
    end

    test "nome que não existe no chat" do
      assert ContextTools.execute("get_user_facts", ~s({"nome": "Zumbi"}), @chat_id) =~
               ~s(Não conheço ninguém chamado "Zumbi")
    end

    test "prefixo único resolve para o membro certo" do
      track(111, "Marcela")
      Memory.upsert_fact("111", "profissão", "dentista")

      result = ContextTools.execute("get_user_facts", ~s({"nome": "marc"}), @chat_id)

      assert result =~ "profissão: dentista"
    end

    test "prefixo ambíguo não devolve fatos da pessoa errada" do
      track(111, "Marcela")
      track(222, "Marcos")
      Memory.upsert_fact("111", "profissão", "dentista")

      result = ContextTools.execute("get_user_facts", ~s({"nome": "mar"}), @chat_id)

      refute result =~ "dentista"
      assert result =~ ~s(Não conheço ninguém chamado "mar")
    end

    test "nome exato ganha de prefixo de outro membro" do
      track(111, "Ana")
      track(222, "Anabela")
      Memory.upsert_fact("111", "cidade", "Recife")

      result = ContextTools.execute("get_user_facts", ~s({"nome": "Ana"}), @chat_id)

      assert result =~ "cidade: Recife"
    end

    test "chamada sem o argumento nome pede o nome de volta" do
      assert ContextTools.execute("get_user_facts", "{}", @chat_id) =~ "informando o nome"
    end

    test "arguments com JSON inválido não quebra" do
      assert ContextTools.execute("get_user_facts", "{nope", @chat_id) =~ "informando o nome"
    end

    test "arguments nil não quebra" do
      assert ContextTools.execute("get_user_facts", nil, @chat_id) =~ "informando o nome"
    end
  end

  describe "get_warns" do
    test "chat sem warns ativos" do
      assert ContextTools.execute("get_warns", "{}", @chat_id) =~ "Ninguém tem warn"
    end

    test "placar ordenado com contadores" do
      Warns.increment(@chat_id, 111, "Marcela")
      Warns.increment(@chat_id, 222, "Beto")
      Warns.increment(@chat_id, 222, "Beto")

      result = ContextTools.execute("get_warns", "{}", @chat_id)

      assert result =~ "Beto: 2"
      assert result =~ "Marcela: 1"
      assert result =~ "limite #{Warns.limit()}"
    end

    test "warn zerado pelo perdão sai do placar" do
      Warns.increment(@chat_id, 111, "Marcela")
      Warns.reset(@chat_id, 111)

      assert ContextTools.execute("get_warns", "{}", @chat_id) =~ "Ninguém tem warn"
    end
  end

  test "ferramenta desconhecida devolve texto em vez de crash" do
    assert ContextTools.execute("get_queijo", "{}", @chat_id) =~ "desconhecida"
  end
end
