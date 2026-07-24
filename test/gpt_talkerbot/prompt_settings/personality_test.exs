defmodule GptTalkerbot.PromptSettings.PersonalityTest do
  use GptTalkerbot.DataCase

  alias GptTalkerbot.{ChatMembers, Memory}
  alias GptTalkerbot.PromptSettings.Personality

  @chat_id "-100424242"

  setup do
    ChatMembers.Cache.reset()
    :ok
  end

  defp track(user_id, first_name) do
    ChatMembers.track(@chat_id, %{"id" => user_id, "first_name" => first_name, "is_bot" => false})
  end

  test "ancora a identidade do interlocutor pelo nome" do
    track(111, "Marcela")

    prompt = Personality.build_system_prompt("111", @chat_id)

    assert prompt =~ "respondendo agora a Marcela"
  end

  test "prega os fatos no nome de quem está falando, não em 'este usuário'" do
    track(111, "Marcela")
    Memory.upsert_fact("111", "profissão", "dentista")

    prompt = Personality.build_system_prompt("111", @chat_id)

    assert prompt =~ "Fatos sobre Marcela"
    refute prompt =~ "Fatos sobre este usuário"
  end

  test "membro desconhecido não quebra e cai no rótulo genérico" do
    Memory.upsert_fact("999", "profissão", "dentista")

    prompt = Personality.build_system_prompt("999", @chat_id)

    refute prompt =~ "respondendo agora a"
    assert prompt =~ "Fatos sobre este usuário"
  end
end
