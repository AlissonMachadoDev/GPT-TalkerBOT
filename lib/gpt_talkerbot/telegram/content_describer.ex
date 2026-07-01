defmodule GptTalkerbot.Telegram.ContentDescriber do
  @moduledoc """
  Converte mensagens não-textuais do Telegram em representação textual,
  para servirem de contexto ao modelo — citações em reply, buffer do grupo.

  Tudo aqui é traduzível a partir dos campos estruturados da API; o
  conteúdo visual de fotos/vídeos fica de fora (exigiria modelo de visão).
  """

  def describe(%{"text" => text}) when is_binary(text) and text != "", do: text

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
