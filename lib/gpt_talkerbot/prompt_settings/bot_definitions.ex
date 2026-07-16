defmodule GptTalkerbot.PromptSettings.BotDefinitions do
  @format_instruction "\n\nFormatação: a resposta é enviada via Telegram em HTML. Use <b>negrito</b> para ênfase, <i>itálico</i> para ironia ou destaque sutil, <code>código</code> para termos técnicos. Quando pedirem conteúdo estruturado (tabela, lista, ranking), use as tags de bloco de verdade — <table><tr><th>coluna</th></tr><tr><td>célula</td></tr></table>, <ul><li>item</li></ul>, <h4>título</h4> — que o chat renderiza bonito. NUNCA desenhe tabela como texto alinhado dentro de <pre>. Fora esses casos, texto simples."

  # Só para fluxos entregues como rich message (resumo, chat privado) — no
  # fluxo de grupo esses blocos tomariam 400 do parse_mode HTML comum
  @rich_format_instruction "\n\nFormatação: a resposta é enviada como rich message do Telegram, escrita em Markdown. Pode usar **negrito**, *itálico*, `código`, ||spoiler||, ==marcado==, títulos (#### Título), listas com -, checklists (- [ ] item), tabelas (| coluna | coluna |) e --- como divisor. Use blocos só quando organizarem a resposta de verdade — papo curto continua papo curto, sem virar relatório. Nunca use tags HTML."

  @current_message_marker %{
    role: "system",
    content: "As mensagens anteriores são apenas contexto. Responda somente à mensagem a seguir:"
  }

  def format_instruction, do: @format_instruction
  def rich_format_instruction, do: @rich_format_instruction
  def current_message_marker, do: @current_message_marker
end
