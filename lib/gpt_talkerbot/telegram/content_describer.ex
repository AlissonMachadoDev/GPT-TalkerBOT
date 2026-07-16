defmodule GptTalkerbot.Telegram.ContentDescriber do
  @moduledoc """
  Converte mensagens não-textuais do Telegram em representação textual,
  para servirem de contexto ao modelo — citações em reply, buffer do grupo.

  Tudo aqui é traduzível a partir dos campos estruturados da API; o
  conteúdo visual de fotos/vídeos fica de fora (exigiria modelo de visão).
  """

  def describe(%{"text" => text}) when is_binary(text) and text != "", do: text

  def describe(%{"rich_message" => rich_message}) when is_map(rich_message) do
    rich_message
    |> rich_message_text()
    |> blank_to_nil()
  end

  def describe(params) when is_map(params) do
    case media_tag(params) do
      nil ->
        nil

      tag ->
        case params["caption"] do
          caption when is_binary(caption) and caption != "" -> tag <> " " <> caption
          _ -> tag
        end
    end
  end

  def describe(_params), do: nil

  defp rich_message_text(%{"blocks" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.map(&rich_block_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp rich_message_text(%{"html" => html}) when is_binary(html), do: strip_markup(html)
  defp rich_message_text(%{"markdown" => markdown}) when is_binary(markdown), do: markdown
  defp rich_message_text(_rich_message), do: ""

  defp rich_block_text(%{"type" => "table", "cells" => rows} = table) when is_list(rows) do
    caption = table["caption"]

    body =
      rows
      |> Enum.map(fn row ->
        row
        |> List.wrap()
        |> Enum.map(&rich_cell_text/1)
        |> Enum.join(" | ")
      end)
      |> Enum.join("\n")

    [caption, body]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join("\n")
  end

  defp rich_block_text(%{"text" => text}) when is_binary(text), do: text
  defp rich_block_text(_block), do: ""

  defp rich_cell_text(%{"text" => text}) when is_binary(text), do: text
  defp rich_cell_text(text) when is_binary(text), do: text
  defp rich_cell_text(_cell), do: ""

  defp strip_markup(markup) do
    markup
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/t[dh]>/i, " | ")
    |> String.replace(~r/<\/(?:tr|p|li|h[1-6])>/i, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text

  defp media_tag(%{"poll" => %{"question" => question} = poll}) do
    options =
      poll["options"]
      |> List.wrap()
      |> Enum.map(& &1["text"])
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    votes = poll["total_voter_count"] || 0
    ~s([enquete: "#{question}" — opções: #{options} | #{votes} votos])
  end

  defp media_tag(%{"dice" => %{"emoji" => emoji, "value" => value}}) do
    "[#{emoji}: caiu #{value}]"
  end

  defp media_tag(%{"sticker" => sticker}) do
    case sticker["emoji"] do
      nil -> "[sticker]"
      emoji -> "[sticker #{emoji}]"
    end
  end

  defp media_tag(%{"voice" => voice}), do: "[áudio de #{voice["duration"] || "?"}s]"
  defp media_tag(%{"video_note" => note}), do: "[vídeo redondo de #{note["duration"] || "?"}s]"

  defp media_tag(%{"audio" => audio}) do
    title = audio["title"] || "sem título"
    "[música: #{title}]"
  end

  # animation antes de photo/video/document: por retrocompatibilidade a API
  # preenche "document" junto com "animation" na mesma mensagem
  defp media_tag(%{"animation" => _}), do: "[GIF]"
  defp media_tag(%{"photo" => _}), do: "[foto]"
  defp media_tag(%{"video" => _}), do: "[vídeo]"
  defp media_tag(%{"document" => doc}), do: "[arquivo #{doc["file_name"] || "sem nome"}]"
  defp media_tag(%{"venue" => %{"title" => title}}), do: "[local: #{title}]"
  defp media_tag(%{"location" => _}), do: "[localização]"
  defp media_tag(%{"contact" => contact}), do: "[contato: #{contact["first_name"]}]"
  defp media_tag(_params), do: nil
end
