defmodule GptTalkerbot.Telegram.RichMessages do
  @moduledoc """
  Builders de payloads InputRichMessage (Bot API 10.1+).

  Uma rich message aceita exatamente um de `html`, `markdown` ou `blocks`.
  Os fluxos rich do bot falam Markdown: o LLM escreve tabelas, títulos e
  listas em Markdown com muito mais confiança do que em HTML, e o campo
  `markdown` da API entende tudo isso direto (ver rich_format_instruction
  em BotDefinitions).
  """

  @doc "Resposta gerada pelo LLM em Markdown, como veio."
  def markdown(md) do
    %{markdown: md}
  end

  @doc "Payload do /resumo: título, recap em Markdown e assinatura."
  def resumo(recap_md) do
    %{markdown: "#### 🐀 Resumo do dia\n\n" <> recap_md <> "\n\n---\n*Ratobô — direto do porão*"}
  end

  @doc """
  Draft com o bloco nativo "thinking" — placeholder animado exibido
  enquanto a resposta real é gerada. Só é aceito em sendRichMessageDraft;
  nunca chega como mensagem persistida.
  """
  def thinking_draft(text) do
    %{blocks: [%{type: "thinking", text: text}]}
  end

  # Tags que o parse_mode HTML comum do Telegram aceita; qualquer outra
  # (table, ul, h1...) derruba o sendMessage com 400
  @parse_mode_tags ~w(b strong i em u ins s strike del a code pre blockquote span tg-spoiler tg-emoji)

  # Elementos de bloco do modo rich que devem passar intactos, sem virar <p>
  @block_element ~r/(<(?:table|ul|ol|details|figure|aside)[\s>].*?<\/(?:table|ul|ol|details|figure|aside)>|<(?:h[1-6]|p)>.*?<\/(?:h[1-6]|p)>|<hr\s*\/?>)/s

  @doc """
  true se o HTML contém alguma tag que o parse_mode comum não reconhece —
  o sinal de que a mensagem precisa ir como rich message.
  """
  def needs_rich_html?(text) do
    ~r/<\/?([a-zA-Z][a-zA-Z0-9-]*)/
    |> Regex.scan(text)
    |> Enum.any?(fn [_, tag] -> String.downcase(tag) not in @parse_mode_tags end)
  end

  @doc """
  Rich message a partir do HTML gerado no fluxo de grupo: elementos de
  bloco (tabela, lista, título...) passam intactos; o texto solto entre
  eles vira parágrafos, senão as quebras de linha colapsam no modo html.
  """
  def from_html(html) do
    content =
      @block_element
      |> Regex.split(html, include_captures: true, trim: true)
      |> Enum.map_join(fn segment ->
        if block_element?(segment), do: segment, else: to_paragraphs(segment)
      end)

    %{html: content}
  end

  @doc """
  Achata os elementos de bloco em texto que o parse_mode comum aceita —
  o plano B quando a rich message é recusada: feio, mas entregue.
  """
  def flatten_html(text) do
    text
    |> String.replace(~r/<\/t[dh]>/i, " | ")
    |> String.replace(~r/<\/(?:tr|li|p|h[1-6])>/i, "\n")
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<hr\s*\/?>/i, "\n———\n")
    |> then(fn flattened ->
      Regex.replace(~r/<\/?([a-zA-Z][a-zA-Z0-9-]*)[^>]*>/, flattened, fn full, tag ->
        if String.downcase(tag) in @parse_mode_tags, do: full, else: ""
      end)
    end)
  end

  defp block_element?(segment) do
    String.match?(segment, ~r/\A<(?:table|ul|ol|details|figure|aside|h[1-6]|p|hr)[\s>\/]/)
  end

  defp to_paragraphs(text) do
    text
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.map_join(fn paragraph ->
      "<p>" <> String.replace(paragraph, "\n", "<br>") <> "</p>"
    end)
  end
end
