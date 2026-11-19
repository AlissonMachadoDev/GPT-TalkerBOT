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

    test "diretiva de voz por nome vira ação de áudio, sem precisar de [[ratobo:audio]]" do
      assert PostActions.extract("ok\n[[ratobo:voice:nome: Michel Teló]]") ==
               {"ok", [:audio, {:voice_name, "Michel Teló"}]}
    end

    test "diretiva de voz por nome combinada com áudio não duplica a ação" do
      assert {"ok", actions} =
               PostActions.extract("ok\n[[ratobo:audio]]\n[[ratobo:voice:nome: Michel Teló]]")

      assert Enum.sort(actions) == [:audio, {:voice_name, "Michel Teló"}]
    end

    test "diretiva de voz por nome aceita variações de caixa e espaço" do
      assert {_, [:audio, {:voice_name, "voz de robô"}]} =
               PostActions.extract("bip\n[[ Ratobo: VOICE:NOME:   voz de robô  ]]")
    end

    test "diretiva de voz por estilo filtra só as palavras do vocabulário fixo" do
      assert PostActions.extract("ok\n[[ratobo:voice:estilo: feminina, jovem]]") ==
               {"ok", [:audio, {:voice_style, ["feminina", "jovem"]}]}
    end

    test "diretiva de estilo descarta palavra fora do vocabulário sem quebrar as demais" do
      assert PostActions.extract("ok\n[[ratobo:voice:estilo: feminina safadenta jovem]]") ==
               {"ok", [:audio, {:voice_style, ["feminina", "jovem"]}]}
    end

    test "diretiva de estilo sem nenhuma palavra reconhecida vira lista vazia" do
      assert PostActions.extract("ok\n[[ratobo:voice:estilo: inventada]]") ==
               {"ok", [:audio, {:voice_style, []}]}
    end
  end

  describe "voice_turns/1" do
    test "sem marcador nenhum não é diálogo" do
      assert PostActions.voice_turns("kkkk clássico do Beto") == []
    end

    test "um marcador só não é diálogo (é troca de voz de fala única)" do
      assert PostActions.voice_turns("[[ratobo:voice:nome:Fulano]] oi") == [
               %{action: {:voice_name, "Fulano"}, text: "oi"}
             ]
    end

    test "dois ou mais marcadores viram uma fala por marcador, em ordem" do
      text =
        "[[ratobo:voice:nome:Fulano]] fala do Fulano.\n" <>
          "[[ratobo:voice:estilo:feminina agressiva]] fala da segunda voz."

      assert PostActions.voice_turns(text) == [
               %{action: {:voice_name, "Fulano"}, text: "fala do Fulano."},
               %{action: {:voice_style, ["feminina", "agressiva"]}, text: "fala da segunda voz."}
             ]
    end

    test "texto antes do primeiro marcador é descartado" do
      text = "isso aqui some\n[[ratobo:voice:nome:Fulano]] isso fica"

      assert PostActions.voice_turns(text) == [
               %{action: {:voice_name, "Fulano"}, text: "isso fica"}
             ]
    end

    test "marcador sem texto depois (fala vazia) não vira turno" do
      text = "[[ratobo:voice:nome:Fulano]] fala de verdade\n[[ratobo:voice:nome:Ciclano]]"

      assert PostActions.voice_turns(text) == [
               %{action: {:voice_name, "Fulano"}, text: "fala de verdade"}
             ]
    end

    test "nil vira lista vazia" do
      assert PostActions.voice_turns(nil) == []
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

    test "direção longa em português, com vírgula, também some" do
      assert PostActions.strip_audio_tags("[sussurrando, fingindo pena] coitado") == "coitado"
    end

    test "tag prosódica some e deixa o trecho que ela envolvia" do
      assert PostActions.strip_audio_tags("é <emphasis>agora</emphasis> ou nunca") ==
               "é agora ou nunca"
    end

    test "direção com dígito não é tratada como tag — é placar do usuário" do
      assert PostActions.strip_audio_tags("[virada de 3x2] que jogo") ==
               "[virada de 3x2] que jogo"
    end

    test "direção longa demais fica no texto em vez de engolir a frase" do
      longa = "[" <> String.duplicate("a", 90) <> "]"
      assert PostActions.strip_audio_tags(longa <> " fim") == longa <> " fim"
    end

    test "colchete de uma letra só não é direção" do
      assert PostActions.strip_audio_tags("item [a] da lista") == "item [a] da lista"
    end

    test "nil vira string vazia" do
      assert PostActions.strip_audio_tags(nil) == ""
    end
  end

  describe "cast/1" do
    test "separa os nomes declarados no marcador" do
      assert PostActions.cast("[[ratobo:bipolar:Silvio Santos, Faustão]]") ==
               ["Silvio Santos", "Faustão"]
    end

    test "espaçamento irregular em volta da vírgula não entra no nome" do
      assert PostActions.cast("[[ratobo:bipolar:  Silvio   ,Faustão  ,  Galvão ]]") ==
               ["Silvio", "Faustão", "Galvão"]
    end

    test "corta o elenco no teto, pra não disparar busca de voz sem fim" do
      marcador = "[[ratobo:bipolar:Um, Dois, Três, Quatro, Cinco, Seis]]"

      assert PostActions.cast(marcador) == ["Um", "Dois", "Três", "Quatro"]
    end

    test "nome repetido com grafia diferente conta uma vez só" do
      assert PostActions.cast("[[ratobo:bipolar:Faustão, FAUSTAO, Galvão]]") ==
               ["Faustão", "Galvão"]
    end

    test "conjunção antes do último nome não fica colada nele" do
      assert PostActions.cast("[[ratobo:bipolar:Silvio Santos, Faustão, e Galvão]]") ==
               ["Silvio Santos", "Faustão", "Galvão"]
    end

    test "'A e B' sem vírgula vira dois personagens, não um nome só" do
      assert PostActions.cast("[[ratobo:bipolar:Silvio Santos e Faustão]]") ==
               ["Silvio Santos", "Faustão"]
    end

    test "'A, B e C' no padrão de lista em português" do
      assert PostActions.cast("[[ratobo:bipolar:Ana, Beto e Caio]]") == ["Ana", "Beto", "Caio"]
    end

    test "nome que começa com 'e' não é confundido com conjunção" do
      assert PostActions.cast("[[ratobo:bipolar:Eduardo, Elza]]") == ["Eduardo", "Elza"]
    end

    test "parênteses protegem o 'e' dentro do nome: uma busca, não duas" do
      assert PostActions.cast("[[ratobo:bipolar:(Chico e Felipe), Galvão]]") ==
               ["Chico e Felipe", "Galvão"]
    end

    test "parênteses protegem vírgula dentro do nome" do
      assert PostActions.cast("[[ratobo:bipolar:(Tom, Jerry), Galvão]]") ==
               ["Tom, Jerry", "Galvão"]
    end

    test "elenco inteiro entre parênteses é um personagem só" do
      assert PostActions.cast("[[ratobo:bipolar:(Chico e Felipe)]]") == ["Chico e Felipe"]
    end

    test "dois grupos protegidos não se embaralham" do
      assert PostActions.cast("[[ratobo:bipolar:(Chico e Felipe), (Sandy e Junior)]]") ==
               ["Chico e Felipe", "Sandy e Junior"]
    end

    test "grupo protegido convive com nome solto separado por conjunção" do
      assert PostActions.cast("[[ratobo:bipolar:(Chico e Felipe), Ana e Beto]]") ==
               ["Chico e Felipe", "Ana", "Beto"]
    end

    test "parênteses vazios não viram personagem" do
      assert PostActions.cast("[[ratobo:bipolar:(), Galvão]]") == ["Galvão"]
    end

    test "preposição arrastada do pedido não entra no nome buscado" do
      assert PostActions.cast("[[ratobo:bipolar:Bea do Bras e da Patricia Poeta]]") ==
               ["Bea do Bras", "Patricia Poeta"]
    end

    test "artigo na frente de cada nome também sai" do
      assert PostActions.cast("[[ratobo:bipolar:a Bea do Bras, o Faustão, as Chiquititas]]") ==
               ["Bea do Bras", "Faustão", "Chiquititas"]
    end

    test "preposição no meio do nome é parte dele e fica" do
      assert PostActions.cast("[[ratobo:bipolar:Bea do Bras, Maria das Dores]]") ==
               ["Bea do Bras", "Maria das Dores"]
    end

    test "sem marcador não há elenco" do
      assert PostActions.cast("kkkk clássico do Beto") == []
    end

    test "marcador vazio não vira elenco de string vazia" do
      assert PostActions.cast("[[ratobo:bipolar: , ,]]") == []
    end

    test "nil vira lista vazia" do
      assert PostActions.cast(nil) == []
    end
  end

  describe "script_turns/2" do
    test "cada linha 'Nome: fala' vira uma fala do elenco" do
      texto = "Silvio: Olha quem chegou.\nFaustão: Ô loco meu."

      assert PostActions.script_turns(texto, ["Silvio", "Faustão"]) == [
               %{name: "Silvio", text: "Olha quem chegou."},
               %{name: "Faustão", text: "Ô loco meu."}
             ]
    end

    test "o mesmo personagem pode voltar a falar" do
      texto = "Silvio: Primeira.\nFaustão: Segunda.\nSilvio: Terceira."

      assert PostActions.script_turns(texto, ["Silvio", "Faustão"]) == [
               %{name: "Silvio", text: "Primeira."},
               %{name: "Faustão", text: "Segunda."},
               %{name: "Silvio", text: "Terceira."}
             ]
    end

    test "primeiro nome resolve pro nome completo do elenco" do
      texto = "Silvio: Olha quem chegou.\nGalvão: E o Brasil ataca."

      assert PostActions.script_turns(texto, ["Silvio Santos", "Galvão Bueno"]) == [
               %{name: "Silvio Santos", text: "Olha quem chegou."},
               %{name: "Galvão Bueno", text: "E o Brasil ataca."}
             ]
    end

    test "acento e caixa não decidem de quem é a fala" do
      texto = "FAUSTAO: Ô loco.\nfaustão: de novo."

      assert PostActions.script_turns(texto, ["Faustão"]) == [
               %{name: "Faustão", text: "Ô loco."},
               %{name: "Faustão", text: "de novo."}
             ]
    end

    test "linha sem nome continua a fala anterior" do
      texto = "Silvio: Primeira linha.\nSegunda linha da mesma fala.\nFaustão: Outra."

      assert PostActions.script_turns(texto, ["Silvio", "Faustão"]) == [
               %{name: "Silvio", text: "Primeira linha.\nSegunda linha da mesma fala."},
               %{name: "Faustão", text: "Outra."}
             ]
    end

    test "narração antes da primeira fala é descartada" do
      texto = "Olha só essa cena:\nSilvio: Começou."

      assert PostActions.script_turns(texto, ["Silvio"]) == [
               %{name: "Silvio", text: "Começou."}
             ]
    end

    test "nome fora do elenco não abre fala — vira continuação" do
      texto = "Silvio: Falei.\nRatobô: Também quero falar."

      assert PostActions.script_turns(texto, ["Silvio"]) == [
               %{name: "Silvio", text: "Falei.\nRatobô: Também quero falar."}
             ]
    end

    test "frase comum terminada em dois-pontos não vira fala" do
      texto = "Silvio: Escuta isso:\nnão é fala de ninguém."

      assert PostActions.script_turns(texto, ["Silvio"]) == [
               %{name: "Silvio", text: "Escuta isso:\nnão é fala de ninguém."}
             ]
    end

    test "nome do elenco sem nada depois dos dois-pontos não vira fala vazia" do
      texto = "Silvio:\nFaustão: Só eu falo."

      assert PostActions.script_turns(texto, ["Silvio", "Faustão"]) == [
               %{name: "Faustão", text: "Só eu falo."}
             ]
    end

    test "marcador no fim da resposta não é lido como parte da última fala" do
      texto = "Silvio: Olha quem chegou.\nFaustão: Ô loco.\n[[ratobo:bipolar:Silvio, Faustão]]"

      assert PostActions.script_turns(texto, ["Silvio", "Faustão"]) == [
               %{name: "Silvio", text: "Olha quem chegou."},
               %{name: "Faustão", text: "Ô loco."}
             ]
    end

    test "marcador no topo não vira fala nem narração" do
      texto = "[[ratobo:bipolar:Silvio, Faustão]]\nSilvio: Um.\nFaustão: Dois."

      assert PostActions.script_turns(texto, ["Silvio", "Faustão"]) == [
               %{name: "Silvio", text: "Um."},
               %{name: "Faustão", text: "Dois."}
             ]
    end

    test "nome protegido casa a fala escrita sem os parênteses" do
      texto = "Chico e Felipe: Nós dois.\nGalvão: Ataca."

      assert PostActions.script_turns(texto, ["Chico e Felipe", "Galvão"]) == [
               %{name: "Chico e Felipe", text: "Nós dois."},
               %{name: "Galvão", text: "Ataca."}
             ]
    end

    test "nome protegido casa mesmo se o modelo repetir os parênteses na fala" do
      texto = "(Chico e Felipe): Nós dois.\nGalvão: Ataca."

      assert PostActions.script_turns(texto, ["Chico e Felipe", "Galvão"]) == [
               %{name: "Chico e Felipe", text: "Nós dois."},
               %{name: "Galvão", text: "Ataca."}
             ]
    end

    test "fala escrita com preposição na frente casa o nome do elenco" do
      texto = "da Patricia Poeta: Que roupa é essa?\nBea do Bras: Me erra."

      assert PostActions.script_turns(texto, ["Bea do Bras", "Patricia Poeta"]) == [
               %{name: "Patricia Poeta", text: "Que roupa é essa?"},
               %{name: "Bea do Bras", text: "Me erra."}
             ]
    end

    test "linha em branco entre falas não cria fala vazia" do
      texto = "Silvio: Um.\n\nFaustão: Dois."

      assert PostActions.script_turns(texto, ["Silvio", "Faustão"]) == [
               %{name: "Silvio", text: "Um."},
               %{name: "Faustão", text: "Dois."}
             ]
    end

    test "texto sem nenhuma fala reconhecida não é cena" do
      assert PostActions.script_turns("kkkk clássico do Beto", ["Silvio"]) == []
    end

    test "elenco vazio não reconhece fala nenhuma" do
      assert PostActions.script_turns("Silvio: oi", []) == []
    end

    test "nil vira lista vazia" do
      assert PostActions.script_turns(nil, ["Silvio"]) == []
    end
  end

  describe "strip/1 com o marcador de elenco" do
    test "marcador bipolar longo some da resposta" do
      texto =
        "[[ratobo:bipolar:Silvio Santos, Faustão, Galvão Bueno, Ana Maria Braga]]\nSilvio: oi"

      assert PostActions.strip(texto) == "Silvio: oi"
    end
  end

  describe "speech_text/1" do
    test "tira o HTML do Telegram" do
      assert PostActions.speech_text("olha o <b>rato</b> aí") == "olha o rato aí"
    end

    test "preserva as tags prosódicas, que vão dirigir a síntese" do
      assert PostActions.speech_text("fala <whisper>baixo</whisper> agora") ==
               "fala <whisper>baixo</whisper> agora"
    end

    test "separa prosódia de HTML na mesma frase" do
      assert PostActions.speech_text("<i>ei</i>, <emphasis>para</emphasis>") ==
               "ei, <emphasis>para</emphasis>"
    end

    test "tag parecida com prosódica mas não listada é tratada como HTML" do
      assert PostActions.speech_text("<slowly>devagar</slowly>") == "devagar"
    end

    test "direção de colchete passa intacta — quem limpa é strip_audio_tags" do
      assert PostActions.speech_text("[quase rindo] <b>oi</b>") == "[quase rindo] oi"
    end

    test "texto sem tag nenhuma sai apenas aparado" do
      assert PostActions.speech_text("  fala pura  ") == "fala pura"
    end

    test "nil vira string vazia" do
      assert PostActions.speech_text(nil) == ""
    end
  end
end
