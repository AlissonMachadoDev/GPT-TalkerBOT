defmodule GptTalkerbot.Telegram.HtmlSanitizerTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Telegram.HtmlSanitizer

  test "retorna vazio para nil (resposta sem content)" do
    assert HtmlSanitizer.truncate(nil) == ""
  end

  test "não altera texto dentro do limite" do
    assert HtmlSanitizer.truncate("oi <b>sumido</b>", 100) == "oi <b>sumido</b>"
  end

  test "trunca texto longo sem tags" do
    assert HtmlSanitizer.truncate(String.duplicate("a", 50), 10) == String.duplicate("a", 10)
  end

  test "remove tag parcial cortada no meio" do
    # corte cai no meio de "<b>"
    text = String.duplicate("a", 9) <> "<b>negrito</b>"
    result = HtmlSanitizer.truncate(text, 11)
    refute result =~ "<"
  end

  test "fecha tag aberta após o truncamento" do
    text = "<b>" <> String.duplicate("a", 50)
    result = HtmlSanitizer.truncate(text, 20)
    assert String.ends_with?(result, "</b>")
  end

  test "fecha tags aninhadas na ordem correta" do
    text = "<b>negrito <i>italico " <> String.duplicate("a", 50)
    result = HtmlSanitizer.truncate(text, 30)
    assert String.ends_with?(result, "</i></b>")
  end

  test "não fecha tags que já estão fechadas" do
    text = "<b>ok</b> " <> String.duplicate("a", 50)
    result = HtmlSanitizer.truncate(text, 20)
    refute String.ends_with?(result, "</b>")
    assert result =~ "<b>ok</b>"
  end
end
