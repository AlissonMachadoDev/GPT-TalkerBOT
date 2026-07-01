defmodule GptTalkerbot.GifMemory do
  @moduledoc """
  Memória de GIFs do bot, por chat: todo GIF (animation) postado no grupo
  é lembrado; de vez em quando (gif_probability) o bot repete um aleatório.

  GIFs banidos via /bangif ficam marcados e nunca voltam — nem quando
  repostados no grupo (o upsert preserva o banimento).
  """

  import Ecto.Query

  alias GptTalkerbot.GifMemory.Gif
  alias GptTalkerbot.Repo
  alias GptTalkerbot.RuntimeEnvs
  alias GptTalkerbotWeb.Services.Telegram

  @doc "Guarda um GIF visto no chat (mantém o banimento se já existir)"
  def remember(chat_id, %{"file_id" => file_id, "file_unique_id" => unique_id}) do
    %Gif{}
    |> Gif.changeset(%{
      chat_id: to_string(chat_id),
      file_id: file_id,
      file_unique_id: unique_id
    })
    |> Repo.insert(
      # file_id pode mudar entre reposts do mesmo GIF; banned fica como está
      on_conflict: [set: [file_id: file_id, updated_at: DateTime.utc_now()]],
      conflict_target: [:chat_id, :file_unique_id]
    )
  end

  def remember(_chat_id, _animation), do: :ok

  @doc "Bane um GIF da memória do chat (controle de conteúdo)"
  def ban(chat_id, file_unique_id) do
    Gif
    |> where([g], g.chat_id == ^to_string(chat_id) and g.file_unique_id == ^file_unique_id)
    |> Repo.update_all(set: [banned: true, updated_at: DateTime.utc_now()])
    |> case do
      {0, _} -> :not_found
      {_, _} -> :ok
    end
  end

  @doc "Com probabilidade gif_probability, manda um GIF aleatório da memória"
  def maybe_send(chat_id) do
    if :rand.uniform() < RuntimeEnvs.get_gif_probability() do
      Task.start(fn -> send_random(chat_id) end)
    end

    :ok
  end

  def send_random(chat_id) do
    case random_gif(chat_id) do
      nil -> :ok
      gif -> Telegram.send_animation(%{chat_id: to_string(chat_id), animation: gif.file_id})
    end
  end

  defp random_gif(chat_id) do
    Gif
    |> where([g], g.chat_id == ^to_string(chat_id) and g.banned == false)
    |> order_by(fragment("RANDOM()"))
    |> limit(1)
    |> Repo.one()
  end
end
