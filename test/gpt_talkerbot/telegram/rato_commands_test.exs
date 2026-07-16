defmodule GptTalkerbot.Telegram.RatoCommandsTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Telegram.RatoCommands

  describe "match_member_options/2" do
    @members [
      %{user_id: "111", first_name: "Fulano"},
      %{user_id: "222", first_name: "Beltrana"},
      %{user_id: "333", first_name: "Xará"},
      %{user_id: "444", first_name: "Xará"},
      %{user_id: "555", first_name: nil}
    ]

    test "pareia opção com membro ignorando caixa e espaços" do
      assert [{"fulano ", %{user_id: "111"}}, {"BELTRANA", %{user_id: "222"}}] =
               RatoCommands.match_member_options(["fulano ", "BELTRANA"], @members)
    end

    test "opção que não é nome de membro passa sem pareamento" do
      assert [{"pizza de abacaxi", nil}] =
               RatoCommands.match_member_options(["pizza de abacaxi"], @members)
    end

    test "nome repetido no grupo não pareia ninguém" do
      assert [{"Xará", nil}] = RatoCommands.match_member_options(["Xará"], @members)
    end

    test "membro sem first_name não quebra o pareamento" do
      assert [{"Fulano", %{user_id: "111"}}] =
               RatoCommands.match_member_options(["Fulano"], @members)
    end
  end
end
