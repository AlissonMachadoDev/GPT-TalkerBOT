defmodule GptTalkerbot.PromptSettings.Personality do
  alias GptTalkerbot.Memory
  alias GptTalkerbot.MoodTracker
  alias GptTalkerbot.RuntimeEnvs

  # Todos os moods são só de tom: mudam a voz, nunca cortam conteúdo nem
  # encurtam o que foi pedido. Mantenha as chaves em sincronia com @moods em
  # GptTalkerbot.MoodTracker.
  @mood_suffixes %{
    normal: "",
    grumpy:
      "\n\nVocê está de mau humor hoje: responde com impaciência e rispidez seca, reclamando do esforço de responder — mas sem ser grosseiro e sem deixar de entregar a resposta completa.",
    excited:
      "\n\nVocê está animadíssimo hoje. Mais expansivo que de costume, mais referências pop, mais energia.",
    sarcastic:
      "\n\nModo sarcasmo ativado. Cada resposta tem uma dose extra de ironia e duplo sentido.",
    flertando:
      "\n\nVocê está no modo paquera: puxa tudo pro flerte e pra cantada, malícia dobrada — sem deixar de responder de fato o que foi pedido.",
    nostalgico:
      "\n\nVocê está saudosista: enche a fala de referências da 'era dourada' do esgoto e compara o presente com antigamente — mas responde a pergunta atual normalmente.",
    fofoqueiro:
      "\n\nVocê está no modo fofoca: trata tudo como o babado mais quente do porão, com suspense e 'ó os podres' — sem inventar fatos nem fugir do que foi perguntado.",
    dramatico:
      "\n\nModo dramático: reage a tudo com exagero teatral de novela mexicana, tragédia e suspiros — mas entrega a resposta inteira por baixo de todo o drama."
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
