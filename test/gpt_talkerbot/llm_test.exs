defmodule GptTalkerbot.LLMTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.LLM

  @tools [
    %{type: "function", function: %{name: "get_group_members", parameters: %{}}},
    %{type: "function", function: %{name: "get_group_context", parameters: %{}}}
  ]

  describe "narrated_tools/2 — nomes de ferramenta vazados como texto" do
    test "um nome sozinho" do
      assert LLM.narrated_tools("get_group_members", @tools) == ["get_group_members"]
    end

    test "vários nomes, um por linha (o caso real reportado)" do
      content = "get_group_members\nget_group_context"
      assert LLM.narrated_tools(content, @tools) == ["get_group_members", "get_group_context"]
    end

    test "nomes separados por vírgula" do
      assert LLM.narrated_tools("get_group_members, get_group_context", @tools) ==
               ["get_group_members", "get_group_context"]
    end

    test "ignora crases e parênteses vazios" do
      assert LLM.narrated_tools("`get_group_members()`", @tools) == ["get_group_members"]
    end

    test "deduplica nomes repetidos" do
      assert LLM.narrated_tools("get_group_members\nget_group_members", @tools) ==
               ["get_group_members"]
    end

    test "resposta de verdade que menciona a ferramenta no meio não dispara" do
      content = "Não vou usar get_group_members agora, já sei quem é o gab."
      assert LLM.narrated_tools(content, @tools) == []
    end

    test "nome desconhecido no meio da lista não dispara" do
      assert LLM.narrated_tools("get_group_members\nfoo_bar", @tools) == []
    end

    test "content vazio ou não-string não dispara" do
      assert LLM.narrated_tools("", @tools) == []
      assert LLM.narrated_tools("   ", @tools) == []
      assert LLM.narrated_tools(nil, @tools) == []
    end
  end
end
