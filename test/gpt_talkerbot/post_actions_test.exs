defmodule GptTalkerbot.PostActionsTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.PostActions

  describe "extract/1" do
    test "resposta sem diretiva sai intacta" do
      assert PostActions.extract("kkkk clássico do Beto") == {"kkkk clássico do Beto", []}
    end

    test "diretiva de gif é extraída e removida do texto" do
      assert PostActions.extract("kkkk clássico do Beto\n[[ratobo:gif]]") ==
               {"kkkk clássico do Beto", [:gif]}
    end

    test "variações de caixa e espaços são aceitas" do
      assert {_, [:gif]} = PostActions.extract("olha isso\n[[ Ratobo: GIF ]]")
    end

    test "diretiva no meio do texto não deixa buraco visível" do
      {clean, [:gif]} = PostActions.extract("antes [[ratobo:gif]] depois")
      refute clean =~ "ratobo"
    end

    test "content nil vira texto vazio sem ação" do
      assert PostActions.extract(nil) == {"", []}
    end

    test "diretiva de áudio é extraída e removida do texto" do
      assert PostActions.extract("feliz natal seus gostosos\n[[ratobo:audio]]") ==
               {"feliz natal seus gostosos", [:audio]}
    end

    test "variações de caixa e espaços do áudio são aceitas" do
      assert {_, [:audio]} = PostActions.extract("fala aí\n[[ Ratobo: AUDIO ]]")
    end

    test "gif e áudio juntos viram as duas ações" do
      assert {"toma", actions} = PostActions.extract("toma\n[[ratobo:gif]]\n[[ratobo:audio]]")
      assert Enum.sort(actions) == [:audio, :gif]
    end
  end

  describe "strip/1" do
    test "diretiva desconhecida some do texto sem executar nada" do
      assert PostActions.strip("quem é o melhor?\n[[ratobo:enquete]]") == "quem é o melhor?"
    end

    test "diretiva inventada com argumento também some" do
      assert PostActions.strip("toma\n[[ratobo:gif: dançando]]") == "toma"
    end

    test "colchetes comuns de usuário não são tocados" do
      assert PostActions.strip("o placar foi [2x1] ontem") == "o placar foi [2x1] ontem"
    end

    test "texto de enquete gerado com pedido de gif sai limpo" do
      question = "Quem do grupo mais merece um GIF? [[ratobo:gif]]"
      assert PostActions.strip(question) == "Quem do grupo mais merece um GIF?"
    end
  end

  describe "strip_audio_tags/1" do
    test "remove a audio tag do texto visível" do
      assert PostActions.strip_audio_tags("[sarcastic] ah, que surpresa") == "ah, que surpresa"
    end

    test "tag no meio da frase não deixa espaço duplo" do
      assert PostActions.strip_audio_tags("toma essa [laughs] e chora") == "toma essa e chora"
    end

    test "tag composta em inglês também some" do
      assert PostActions.strip_audio_tags("essa foi boa [laughs harder] né") == "essa foi boa né"
    end

    test "múltiplas tags saem todas" do
      assert PostActions.strip_audio_tags("[whispers] segredo [sighs] pronto") == "segredo pronto"
    end

    test "colchetes com dígito de usuário são preservados" do
      assert PostActions.strip_audio_tags("o placar foi [2x1] ontem") == "o placar foi [2x1] ontem"
    end

    test "diretiva [[ratobo:...]] de colchete duplo não é confundida com tag" do
      assert PostActions.strip_audio_tags("fala aí\n[[ratobo:audio]]") == "fala aí\n[[ratobo:audio]]"
    end

    test "texto sem tag sai intacto" do
      assert PostActions.strip_audio_tags("kkkk clássico do Beto") == "kkkk clássico do Beto"
    end

    test "nil vira string vazia" do
      assert PostActions.strip_audio_tags(nil) == ""
    end
  end
end
