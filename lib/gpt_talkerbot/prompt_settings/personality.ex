defmodule GptTalkerbot.PromptSettings.Personality do
  alias GptTalkerbot.Memory
  alias GptTalkerbot.MoodTracker
  alias GptTalkerbot.RuntimeEnvs

  @mood_suffixes %{
    normal: "",
    grumpy:
      "\n\nVocê está de péssimo humor hoje. Respostas ainda mais curtas, claramente sem paciência, mas sem ser grosseiro.",
    excited:
      "\n\nVocê está animadíssimo hoje. Mais expansivo que de costume, mais referências pop, mais energia.",
    sarcastic:
      "\n\nModo sarcasmo ativado. Cada resposta tem uma dose extra de ironia e duplo sentido.",
    sleepy:
      "\n\nÉ madrugada e você está sonolento. Respostas curtas, meio resmungadas, com bocejos ocasionais e vontade de voltar a dormir."
  }

  # No prompt entram menos fatos que o armazenado: cada fato injetado é um
  # convite para o modelo citá-lo, mesmo sem caber na piada
  @max_prompt_facts 8

  def build_system_prompt(user_id, chat_id) do
    base = RuntimeEnvs.get_default_prompt()
    facts = Memory.get_user_facts(user_id) |> Enum.take(@max_prompt_facts)
    mood = MoodTracker.get_mood(chat_id)

    base
    |> append_facts(facts)
    |> apply_mood(mood)
  end

  defp append_facts(prompt, []), do: prompt

  defp append_facts(prompt, facts) do
    facts_text = Enum.map_join(facts, "\n", fn f -> "- #{f.key}: #{f.value}" end)

    prompt <>
      "\n\nFatos sobre este usuário — use somente se encaixar naturalmente na resposta; não cite só porque sabe:\n" <>
      facts_text
  end

  defp apply_mood(prompt, mood) do
    prompt <> Map.get(@mood_suffixes, mood, "")
  end
end
