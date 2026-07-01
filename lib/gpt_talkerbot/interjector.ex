defmodule GptTalkerbot.Interjector do
  @moduledoc """
  Intromissão espontânea: com probabilidade pequena e cooldown por chat,
  o bot comenta a conversa do grupo sem ter sido chamado.

  Probabilidade e cooldown vêm do RuntimeEnvs (interject_probability,
  interject_cooldown_minutes).
  """

  use GenServer

  require Logger

  alias GptTalkerbot.{GroupMessageCache, LLM, RuntimeEnvs}
  alias GptTalkerbot.PromptSettings.BotDefinitions
  alias GptTalkerbot.Telegram.HtmlSanitizer
  alias GptTalkerbotWeb.Services.Telegram

  # Sem um mínimo de conversa não há o que comentar
  @min_recent_messages 3

  @interject_instruction """

  Você estava bisbilhotando a conversa do grupo abaixo e resolveu se intrometer \
  sem ninguém ter te chamado. Solte UM comentário curto e espontâneo sobre o que \
  estão falando — uma piada, uma provocação leve ou uma observação debochada. \
  Não cumprimente, não explique que você é um bot, não faça perguntas genéricas.
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Rola o dado para o chat; se passar na probabilidade e no cooldown, intromete"
  def maybe_interject(chat_id) do
    GenServer.cast(__MODULE__, {:maybe_interject, to_string(chat_id)})
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:maybe_interject, chat_id}, last_interjections) do
    now = System.monotonic_time(:second)
    cooldown = RuntimeEnvs.get_interject_cooldown_minutes() * 60
    off_cooldown? = now - Map.get(last_interjections, chat_id, -cooldown) >= cooldown

    if off_cooldown? and :rand.uniform() < RuntimeEnvs.get_interject_probability() do
      Task.start(fn -> interject(chat_id) end)
      {:noreply, Map.put(last_interjections, chat_id, now)}
    else
      {:noreply, last_interjections}
    end
  end

  defp interject(chat_id) do
    recent = GroupMessageCache.get_recent(chat_id, 12)

    if length(recent) >= @min_recent_messages do
      Telegram.send_typing(chat_id)

      transcript =
        Enum.map_join(recent, "\n", fn m -> "#{m.sender_name}: #{m.content}" end)

      system_prompt =
        RuntimeEnvs.get_default_prompt() <>
          @interject_instruction <>
          GptTalkerbot.ChatMembers.prompt_section(chat_id) <>
          BotDefinitions.format_instruction()

      messages = [%{role: "user", content: "Conversa do grupo:\n" <> transcript}]

      case LLM.complete_text(messages, prompt: system_prompt, max_tokens: 300) do
        {:ok, comment} ->
          reply = HtmlSanitizer.truncate(comment)
          Telegram.send_message(%{chat_id: chat_id, text: reply, parse_mode: "HTML"})
          GroupMessageCache.add_bot_message(chat_id, reply)

        {:error, reason} ->
          Logger.warning("Interjector: AI call failed: #{inspect(reason)}")
      end
    end
  end
end
