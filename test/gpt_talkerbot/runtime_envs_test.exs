defmodule GptTalkerbot.RuntimeEnvsTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.RuntimeEnvs

  describe "parse_user_labels/1" do
    test "faz parse de pares id:label separados por ponto-e-vírgula" do
      assert RuntimeEnvs.parse_user_labels("123:o brabo;456:estagiário") == %{
               "123" => "o brabo",
               "456" => "estagiário"
             }
    end

    test "remove aspas e espaços das labels" do
      assert RuntimeEnvs.parse_user_labels(~s(123: "o brabo" )) == %{"123" => "o brabo"}
    end

    test "label com dois-pontos no valor é preservada" do
      assert RuntimeEnvs.parse_user_labels("123:rei do 2:1") == %{"123" => "rei do 2:1"}
    end

    test "ignora pares malformados" do
      assert RuntimeEnvs.parse_user_labels("sem-separador;123:ok") == %{"123" => "ok"}
    end

    test "string vazia vira mapa vazio" do
      assert RuntimeEnvs.parse_user_labels("") == %{}
    end
  end
end
