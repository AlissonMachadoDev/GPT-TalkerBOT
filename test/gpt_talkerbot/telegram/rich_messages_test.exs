defmodule GptTalkerbot.Telegram.RichMessagesTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Telegram.RichMessages

  describe "markdown/1" do
    test "entrega o texto como campo markdown, sem mexer" do
      md = "**Fulano** pagou mico\n\n| réu | crime |\n|---|---|\n| Beltrano | crypto às 3h |"

      assert RichMessages.markdown(md) == %{markdown: md}
    end
  end

  describe "resumo/1" do
    test "envolve o recap com título e assinatura em markdown" do
      %{markdown: md} = RichMessages.resumo("o grupo brigou por causa de pizza")

      assert String.starts_with?(md, "#### 🐀 Resumo do dia\n\n")
      assert md =~ "o grupo brigou por causa de pizza"
      assert String.ends_with?(md, "\n\n---\n*Ratobô — direto do porão*")
    end

    test "preserva blocos markdown do recap (tabela)" do
      %{markdown: md} = RichMessages.resumo("| réu | crime |\n|---|---|\n| Fulano | sumiço |")

      assert md =~ "| réu | crime |"
    end
  end

  describe "needs_rich_html?/1" do
    test "tags do parse_mode comum não disparam rich" do
      refute RichMessages.needs_rich_html?("oi <b>sumido</b>, <i>saudade</i> <code>zero</code>")
      refute RichMessages.needs_rich_html?("<blockquote>citação</blockquote> e <pre>code</pre>")
      refute RichMessages.needs_rich_html?("2 < 3 e ele mandou <3")
    end

    test "tabela, lista e título disparam rich, mesmo em maiúsculas" do
      assert RichMessages.needs_rich_html?("segue: <table><tr><td>x</td></tr></table>")
      assert RichMessages.needs_rich_html?("<ul><li>item</li></ul>")
      assert RichMessages.needs_rich_html?("<h4>título</h4>")
      assert RichMessages.needs_rich_html?("<TABLE BE>lixo</TABLE>")
    end
  end

  describe "from_html/1" do
    test "tabela passa intacta e o texto ao redor vira parágrafos" do
      html =
        "Lá vai a listinha:\n\n<table><tr><td>buraco</td><td>R$ 180</td></tr></table>\n\nFoda-se."

      assert %{html: result} = RichMessages.from_html(html)
      assert result =~ "<p>Lá vai a listinha:</p>"
      assert result =~ "<table><tr><td>buraco</td><td>R$ 180</td></tr></table>"
      assert result =~ "<p>Foda-se.</p>"
    end

    test "texto sem blocos vira só parágrafos" do
      assert RichMessages.from_html("oi\ntudo?") == %{html: "<p>oi<br>tudo?</p>"}
    end
  end

  describe "flatten_html/1" do
    test "achata tabela em linhas com separador, preservando tags do parse_mode" do
      html = "<b>tabela</b>:<table><tr><td>traseira</td><td>R$ 600</td></tr></table>"

      assert RichMessages.flatten_html(html) == "<b>tabela</b>:traseira | R$ 600 | \n"
    end

    test "lista vira linhas" do
      assert RichMessages.flatten_html("<ul><li>um</li><li>dois</li></ul>") == "um\ndois\n"
    end
  end

  describe "thinking_draft/1" do
    test "monta o bloco thinking com o texto dado" do
      assert %{blocks: [%{type: "thinking", text: "farejando..."}]} =
               RichMessages.thinking_draft("farejando...")
    end
  end
end
