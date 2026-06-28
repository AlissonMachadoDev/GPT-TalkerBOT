defmodule GptTalkerbot.PromptSettings.BotDefinitions do
  @format_instruction "\n\nFormatação: a resposta é enviada via Telegram com parse_mode HTML. Use <b>negrito</b> para ênfase, <i>itálico</i> para ironia ou destaque sutil, <code>código</code> para termos técnicos. Fora isso, texto simples."

  def format_instruction, do: @format_instruction
end
