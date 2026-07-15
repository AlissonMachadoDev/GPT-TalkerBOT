defmodule GptTalkerbot.MoodTrackerTest do
  use ExUnit.Case

  alias GptTalkerbot.MoodTracker

  # Deve espelhar @moods em GptTalkerbot.MoodTracker
  @moods [:normal, :grumpy, :excited, :sarcastic, :flertando, :nostalgico, :fofoqueiro, :dramatico]

  test "mood vigente é sempre um dos moods válidos" do
    assert MoodTracker.get_mood() in @moods
  end

  test "get_mood ignora o chat_id: o humor é global" do
    assert MoodTracker.get_mood("chat-a") == MoodTracker.get_mood("chat-b")
  end

  test "reset re-sorteia para um mood diferente do atual, sempre válido" do
    for _ <- 1..20 do
      previous = MoodTracker.get_mood()
      MoodTracker.reset()
      current = MoodTracker.get_mood()

      assert current in @moods
      assert current != previous
    end
  end
end
