defmodule GptTalkerbot.Personality do
  alias GptTalkerbot.Memory
  alias GptTalkerbot.RuntimeEnvs.GenServer, as: RuntimeEnvs

  @mood_suffixes %{
    normal: "",
    grumpy:
      "\n\nVocê está de péssimo humor hoje. Respostas ainda mais curtas, claramente sem paciência, mas sem ser grosseiro.",
    excited:
      "\n\nVocê está animadíssimo hoje. Mais expansivo que de costume, mais referências pop, mais energia.",
    sarcastic:
      "\n\nModo sarcasmo ativado. Cada resposta tem uma dose extra de ironia e duplo sentido."
  }

  def build_system_prompt(user_id) do
    base = Application.get_env(:gpt_talkerbot, :default_prompt, "")
    facts = Memory.get_user_facts(user_id)
    mood = RuntimeEnvs.get_mood()

    base
    |> append_facts(facts)
    |> apply_mood(mood)
  end

  defp append_facts(prompt, []), do: prompt

  defp append_facts(prompt, facts) do
    facts_text = Enum.map_join(facts, "\n", fn f -> "- #{f.key}: #{f.value}" end)
    prompt <> "\n\nO que você já sabe sobre este usuário:\n" <> facts_text
  end

  defp apply_mood(prompt, mood) do
    prompt <> Map.get(@mood_suffixes, mood, "")
  end
end
