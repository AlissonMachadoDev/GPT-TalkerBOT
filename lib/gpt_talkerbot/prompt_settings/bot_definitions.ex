defmodule GptTalkerbot.PromptSettings.BotDefinitions do
  @format_instruction "\n\nFormatação: a resposta é enviada via Telegram com parse_mode HTML. Use <b>negrito</b> para ênfase, <i>itálico</i> para ironia ou destaque sutil, <code>código</code> para termos técnicos. Fora isso, texto simples."

  @current_message_marker %{role: "system", content: "As mensagens anteriores são apenas contexto. Responda somente à mensagem a seguir:"}

  def format_instruction, do: @format_instruction
  def current_message_marker, do: @current_message_marker
end
