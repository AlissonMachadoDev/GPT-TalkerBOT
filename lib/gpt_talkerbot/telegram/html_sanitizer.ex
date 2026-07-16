defmodule GptTalkerbot.Telegram.HtmlSanitizer do
  @moduledoc """
  Truncamento seguro de respostas enviadas com parse_mode HTML.

  Uma tag cortada no meio ("<b" no fim) ou deixada aberta faz o Telegram
  rejeitar a mensagem inteira com 400 — o usuário recebe silêncio. Por isso
  o fechamento de tags abertas roda em toda mensagem, mesmo dentro do
  limite: o LLM às vezes abre uma tag e esquece de fechar.
  """

  @default_max_length 3500

  def truncate(text, max_length \\ @default_max_length)

  def truncate(nil, _max_length), do: ""

  def truncate(text, max_length) do
    if String.length(text) <= max_length do
      close_open_tags(text)
    else
      text
      |> String.slice(0, max_length)
      |> String.replace(~r/<[^>]*$/, "")
      |> close_open_tags()
    end
  end

  defp close_open_tags(text) do
    ~r/<(\/?)([a-z]+)(?:\s[^>]*)?>/
    |> Regex.scan(text)
    |> Enum.reduce([], fn
      [_, "", tag], stack -> [tag | stack]
      [_, "/", tag], stack -> List.delete(stack, tag)
    end)
    |> Enum.map_join(fn tag -> "</#{tag}>" end)
    |> then(&(text <> &1))
  end
end
