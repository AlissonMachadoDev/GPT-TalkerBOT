defmodule GptTalkerbot.PostActions do
  @moduledoc """
  Diretivas de pós-ação embutidas na resposta do LLM.

  Ações que não mudam o texto da resposta (anexar um GIF) não justificam
  outra rodada de tool calling — o modelo sinaliza com um marcador no fim
  da resposta e o pipeline executa depois de extraí-lo.

  O marcador é namespaced ([[ratobo:...]]) de propósito: usuário digitando
  o marcador numa mensagem não aciona nada (só a saída do bot é parseada),
  e qualquer variante — inclusive inventada pelo modelo — é removida do
  texto antes do envio, execute ou não.
  """

  @gif_directive ~r/\[\[\s*ratobo:\s*gif\s*\]\]/iu
  @audio_directive ~r/\[\[\s*ratobo:\s*audio\s*\]\]/iu
  @any_directive ~r/\[\[\s*ratobo:[^\]]{0,60}\]\]/iu

  @instruction "\n\nPara anexar um GIF aleatório da sua coleção à resposta, termine com o " <>
                 "marcador [[ratobo:gif]] em uma linha própria. Use raramente, só quando um GIF " <>
                 "somar à piada. O marcador nunca pode ser a resposta inteira: escreva sempre " <>
                 "uma frase de verdade antes dele, que sirva de legenda pro GIF. Nunca mencione " <>
                 "o marcador no texto nem o use em enquetes." <>
                 "\n\nQuando pedirem um áudio, nota de voz ou pra você 'falar' algo, termine a " <>
                 "resposta com o marcador [[ratobo:audio]] em uma linha própria — ela vira nota " <>
                 "de voz. Nesse caso escreva a fala em texto puro, sem HTML nem emojis, porque " <>
                 "vai ser lida por um sintetizador. Não descreva o áudio ('*áudio de 10s*'): " <>
                 "escreva a fala de verdade."

  def instruction, do: @instruction

  @doc "Separa o texto limpo das pós-ações sinalizadas nele"
  def extract(nil), do: {"", []}

  def extract(text) do
    actions =
      [{@gif_directive, :gif}, {@audio_directive, :audio}]
      |> Enum.filter(fn {directive, _action} -> Regex.match?(directive, text) end)
      |> Enum.map(fn {_directive, action} -> action end)

    {strip(text), actions}
  end

  @doc "Remove qualquer diretiva do texto, inclusive as desconhecidas"
  def strip(nil), do: ""

  def strip(text) do
    text
    |> String.replace(@any_directive, "")
    |> String.trim()
  end
end
