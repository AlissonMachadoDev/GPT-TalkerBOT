defmodule GptTalkerbot.MoodTrackerTest do
  use ExUnit.Case

  alias GptTalkerbot.MoodTracker
  alias GptTalkerbot.RuntimeEnvs

  setup do
    # Fixa o horário local em meio-dia (fora da janela :sleepy) e encurta
    # a duração dos moods para o teste
    offset = 12 - DateTime.utc_now().hour
    previous = :persistent_term.get(RuntimeEnvs, nil)
    :persistent_term.put(RuntimeEnvs, %{utc_offset: offset, mood_duration: 2})

    on_exit(fn ->
      if previous do
        :persistent_term.put(RuntimeEnvs, previous)
      else
        :persistent_term.erase(RuntimeEnvs)
      end
    end)

    {:ok, chat_id: "test-chat-#{System.unique_integer([:positive])}"}
  end

  test "mood começa normal", %{chat_id: chat_id} do
    assert MoodTracker.get_mood(chat_id) == :normal
  end

  test "cadência de respostas dispara mood e decai para normal", %{chat_id: chat_id} do
    for _ <- 1..20, do: MoodTracker.bump(chat_id)
    assert MoodTracker.get_mood(chat_id) == :sarcastic

    # mood_duration = 2: duas respostas depois volta ao normal
    for _ <- 1..2, do: MoodTracker.bump(chat_id)
    assert MoodTracker.get_mood(chat_id) == :normal
  end

  test "insulto dirigido ao bot vira grumpy", %{chat_id: chat_id} do
    MoodTracker.react_to_text(chat_id, "ratobô seu inútil")
    assert MoodTracker.get_mood(chat_id) == :grumpy
  end

  test "mensagem sem insulto não muda o mood", %{chat_id: chat_id} do
    MoodTracker.react_to_text(chat_id, "ratobô me conta uma piada")
    assert MoodTracker.get_mood(chat_id) == :normal
  end

  test "rajada de mensagens no grupo vira excited", %{chat_id: chat_id} do
    for _ <- 1..10, do: MoodTracker.note_activity(chat_id)
    assert MoodTracker.get_mood(chat_id) == :excited
  end

  test "mood é isolado por chat", %{chat_id: chat_id} do
    other = "test-chat-#{System.unique_integer([:positive])}"
    MoodTracker.react_to_text(chat_id, "ratobô seu lixo")

    assert MoodTracker.get_mood(chat_id) == :grumpy
    assert MoodTracker.get_mood(other) == :normal
  end
end
