defmodule GptTalkerbot.DailySummary do
  @moduledoc """
  Posta o "resumo do dia" (recap debochado das mensagens das últimas 24h) em
  cada grupo permitido, uma vez por dia no horário configurado.

  Horário local via RuntimeEnvs (daily_summary_hour + utc_offset).
  daily_summary_hour fora de 0..23 desativa o recurso.
  """

  use GenServer

  require Logger

  alias GptTalkerbot.{GroupMessageCache, LLM, RuntimeEnvs}
  alias GptTalkerbot.PromptSettings.BotDefinitions
  alias GptTalkerbot.Telegram.HtmlSanitizer
  alias GptTalkerbotWeb.Services.Telegram

  # Quando desativado, re-verifica a config de tempos em tempos
  @disabled_recheck_ms 6 * 60 * 60 * 1_000

  # Janela real do "dia": só o que rolou nas últimas 24h entra no resumo
  @window_hours 24

  @recap_instruction """

  Abaixo está a conversa do grupo nas últimas 24 horas. Escreva o "resumo do dia" \
  do Ratobô: debochado, curto, tirando sarro dos assuntos e de quem participou, \
  sem inventar fatos que não estejam nas mensagens. Comece anunciando que é o resumo do dia.
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_next()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run, state) do
    if RuntimeEnvs.get_daily_summary_hour() in 0..23 do
      Task.start(fn -> post_summaries() end)
    end

    schedule_next()
    {:noreply, state}
  end

  defp schedule_next do
    hour = RuntimeEnvs.get_daily_summary_hour()

    delay_ms =
      if hour in 0..23 do
        ms_until_local_hour(hour)
      else
        @disabled_recheck_ms
      end

    Process.send_after(self(), :run, delay_ms)
  end

  defp ms_until_local_hour(hour) do
    now_local = DateTime.add(DateTime.utc_now(), RuntimeEnvs.get_utc_offset() * 3600)
    target = %{now_local | hour: hour, minute: 0, second: 0, microsecond: {0, 0}}

    target =
      if DateTime.compare(target, now_local) == :gt do
        target
      else
        DateTime.add(target, 24 * 3600)
      end

    max(DateTime.diff(target, now_local, :millisecond), 1_000)
  end

  defp post_summaries do
    cutoff = DateTime.utc_now() |> DateTime.add(-@window_hours * 3600)

    Enum.each(RuntimeEnvs.get_allowed_groups(), fn chat_id ->
      case GroupMessageCache.messages_since(chat_id, cutoff) do
        [] -> :ok
        messages -> post_summary(chat_id, messages)
      end
    end)
  end

  defp post_summary(chat_id, messages) do
    system_prompt =
      RuntimeEnvs.get_default_prompt() <>
        @recap_instruction <> BotDefinitions.format_instruction()

    llm_messages = [
      %{
        role: "user",
        content: "Conversa do grupo nas últimas 24h:\n" <> GroupMessageCache.format_transcript(messages)
      }
    ]

    case LLM.complete_text(llm_messages, prompt: system_prompt, max_tokens: 500) do
      {:ok, recap} ->
        Telegram.send_message(%{
          chat_id: to_string(chat_id),
          text: HtmlSanitizer.truncate(recap),
          parse_mode: "HTML"
        })

      {:error, reason} ->
        Logger.warning("DailySummary: AI call failed for chat #{chat_id}: #{inspect(reason)}")
    end
  end
end
