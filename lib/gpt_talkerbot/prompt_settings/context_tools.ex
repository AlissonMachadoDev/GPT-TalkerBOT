defmodule GptTalkerbot.PromptSettings.ContextTools do
  @moduledoc """
  Ferramentas de contexto sob demanda para o fluxo principal de conversa.

  Em vez de injetar lista de membros e pano de fundo do grupo em todo
  system prompt, o modelo consulta via tool calling só quando a mensagem
  pede — contexto irrelevante no prompt convida o modelo a usá-lo.
  """

  alias GptTalkerbot.{ChatMembers, Memory, Warns}
  alias GptTalkerbot.PromptSettings.GroupContext

  @prompt_hint "\n\nVocê tem ferramentas para consultar quem está no chat, o pano de fundo " <>
                 "das conversas recentes, o que você sabe sobre uma pessoa específica e o " <>
                 "placar de warns. Use-as quando a mensagem envolver os membros do grupo " <>
                 "ou fizer referência a algo que você não vê no histórico. " <>
                 "Nunca escreva o nome de uma ferramenta na resposta: ou chame a " <>
                 "ferramenta de verdade, ou responda sem ela."

  def prompt_hint, do: @prompt_hint

  def specs do
    [
      %{
        type: "function",
        function: %{
          name: "get_group_members",
          description:
            "Lista as pessoas deste chat e como mencioná-las com notificação. " <>
              "Use quando a mensagem pedir algo sobre os membros do grupo: apelidar, " <>
              "sortear, comparar, listar ou mencionar alguém específico.",
          parameters: %{type: "object", properties: %{}}
        }
      },
      %{
        type: "function",
        function: %{
          name: "get_group_context",
          description:
            "Resumo do que o grupo conversou recentemente (tópicos, decisões, humor geral). " <>
              "Use quando a mensagem fizer referência a assuntos do grupo que não aparecem " <>
              "no histórico visível.",
          parameters: %{type: "object", properties: %{}}
        }
      },
      %{
        type: "function",
        function: %{
          name: "get_user_facts",
          description:
            "Fatos que você já aprendeu sobre uma pessoa específica do chat. " <>
              "Use quando perguntarem o que você sabe sobre alguém ou quando a resposta " <>
              "pedir detalhes de uma pessoa que não é quem está falando.",
          parameters: %{
            type: "object",
            properties: %{
              nome: %{
                type: "string",
                description: "Primeiro nome da pessoa, como aparece no chat"
              }
            },
            required: ["nome"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "get_warns",
          description:
            "Placar de warns do chat: quem tem avisos oficiais ativos e quantos, " <>
              "do limite de #{Warns.limit()}. Use para zombar de reincidentes ou quando " <>
              "perguntarem sobre warns.",
          parameters: %{type: "object", properties: %{}}
        }
      }
    ]
  end

  # arguments chega como string JSON da API; inválido vira mapa vazio para a
  # tool responder "não achei" em vez de derrubar o processamento da mensagem
  def execute(name, arguments, chat_id) do
    args =
      case Jason.decode(arguments || "{}") do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    run(name, args, chat_id)
  end

  defp run("get_group_members", _args, chat_id) do
    case ChatMembers.prompt_section(chat_id) do
      "" -> "Nenhum membro registrado ainda neste chat."
      section -> String.trim(section)
    end
  end

  defp run("get_group_context", _args, chat_id) do
    case GroupContext.get_context(chat_id) do
      "" ->
        "Nenhum pano de fundo registrado ainda para este grupo."

      context ->
        "Pano de fundo do grupo — serve só para entender referências; " <>
          "não traga esses assuntos de volta por conta própria:\n" <> context
    end
  end

  defp run("get_user_facts", %{"nome" => nome}, chat_id) when is_binary(nome) do
    case find_member(chat_id, nome) do
      nil ->
        ~s(Não conheço ninguém chamado "#{nome}" neste chat.)

      member ->
        case Memory.get_user_facts(member.user_id) do
          [] ->
            "Ainda não sei nada sobre #{member.first_name}."

          facts ->
            "Fatos sobre #{member.first_name} — use somente se encaixar naturalmente " <>
              "na resposta; não cite só porque sabe:\n" <>
              Enum.map_join(facts, "\n", fn f -> "- #{f.key}: #{f.value}" end)
        end
    end
  end

  defp run("get_user_facts", _args, _chat_id),
    do: "Fatos de quem? Chame de novo informando o nome da pessoa."

  defp run("get_warns", _args, chat_id) do
    case Warns.list_counts(chat_id) do
      [] ->
        "Ninguém tem warn ativo neste chat. Ficha limpa geral, suspeito."

      counts ->
        "Placar de warns do chat (limite #{Warns.limit()}, depois o rato perdoa e zera):\n" <>
          Enum.map_join(counts, "\n", fn {name, count} -> "- #{name}: #{count}" end)
    end
  end

  defp run(name, _args, _chat_id), do: "Ferramenta desconhecida: #{name}"

  # Nome exato ganha sempre. Prefixo só resolve se for único: com dois
  # membros casando o prefixo, devolver o primeiro (ordem alfabética)
  # atribuía fatos à pessoa errada — melhor dizer "não conheço".
  defp find_member(chat_id, nome) do
    alvo = String.downcase(String.trim(nome))
    members = ChatMembers.list_members(chat_id)

    exact = Enum.find(members, fn m -> String.downcase(m.first_name || "") == alvo end)

    exact || unique_prefix_match(members, alvo)
  end

  defp unique_prefix_match(members, alvo) do
    members
    |> Enum.filter(fn m -> String.starts_with?(String.downcase(m.first_name || ""), alvo) end)
    |> case do
      [only] -> only
      _ -> nil
    end
  end
end
