defmodule GptTalkerbot.Telegram.RatoCommands do
  @moduledoc """
  Comandos públicos in-character do Ratobô.

    /humor   - mostra o mood atual do chat
    /fatos   - lista o que o bot sabe sobre o usuário
    /esquece - apaga os fatos guardados sobre o usuário
    /resumo  - recap debochado do contexto recente do grupo
  """

  require Logger

  alias GptTalkerbot.{LLM, Memory, MoodTracker, RuntimeEnvs}
  alias GptTalkerbot.PromptSettings.{BotDefinitions, GroupContext}
  alias GptTalkerbot.Telegram.HtmlSanitizer
  alias GptTalkerbotWeb.Services.Telegram

  @commands ~w(humor fatos esquece resumo)

  @mood_lines %{
    normal: "Tudo nos conformes no porão. Humor estável, estoque de queijo em dia. 🧀",
    grumpy: "Péssimo. Não me testa hoje. 🐀",
    excited: "HOJE TÁ BOM DEMAIS! Pergunta qualquer coisa, EU RESPONDO TUDO! ⚡",
    sarcastic: "Ah, meu humor? Impecável. Como sempre. Nota-se, né? 🙄",
    sleepy: "zzz... hã? tô acordado, tô acordado... o que você queria mesmo? 😴"
  }

  @resumo_instruction """

  Abaixo está o resumo neutro do que rolou no grupo recentemente. Reescreva como \
  o "resumo do dia" do Ratobô: debochado, curto, tirando sarro dos assuntos e de \
  quem participou, sem inventar fatos que não estejam no resumo.
  """

  def commands, do: @commands

  def handle("humor", %{"chat" => %{"id" => chat_id}} = message) do
    mood = MoodTracker.get_mood(chat_id)
    reply(message, Map.get(@mood_lines, mood, @mood_lines.normal))
  end

  def handle("fatos", %{"from" => %{"id" => user_id}} = message) do
    case Memory.get_user_facts(to_string(user_id)) do
      [] ->
        reply(message, "Meus sensores ainda não captaram nada sobre você. Suspeito. 🐀")

      facts ->
        facts_text = Enum.map_join(facts, "\n", fn f -> "• <b>#{f.key}</b>: #{f.value}" end)

        reply(
          message,
          "O que meus sensores captaram sobre você:\n\n#{facts_text}\n\n<i>/esquece se quiser que eu formate essa memória.</i>"
        )
    end
  end

  def handle("esquece", %{"from" => %{"id" => user_id}} = message) do
    Memory.clear_user_facts(to_string(user_id))
    reply(message, "Feito. Memória formatada, disco limpo. Você é um estranho pra mim agora. 🐀")
  end

  def handle("resumo", %{"chat" => %{"id" => chat_id}} = message) do
    case GroupContext.get_context(chat_id) do
      "" ->
        reply(message, "Resumo do dia: nada. Absolutamente nada digno de nota aconteceu aqui. 🧀")

      context ->
        reply(message, roast_recap(context))
    end
  end

  def handle(_command, _message), do: :ok

  defp roast_recap(context) do
    system_prompt =
      RuntimeEnvs.get_default_prompt() <>
        @resumo_instruction <> BotDefinitions.format_instruction()

    messages = [%{role: "user", content: "Resumo neutro:\n" <> context}]

    case LLM.complete_text(messages, prompt: system_prompt, max_tokens: 500) do
      {:ok, recap} ->
        HtmlSanitizer.truncate(recap)

      {:error, reason} ->
        Logger.warning("RatoCommands: recap AI call failed: #{inspect(reason)}")
        "Meu redator interno travou, vai o rascunho cru mesmo:\n\n" <> context
    end
  end

  # ClientInputs.SendMessage espera chat_id/message_id como string
  defp reply(%{"chat" => %{"id" => chat_id}, "message_id" => message_id}, text) do
    Telegram.send_message(%{
      chat_id: to_string(chat_id),
      text: text,
      reply_to_message_id: to_string(message_id),
      parse_mode: "HTML"
    })
  end
end
