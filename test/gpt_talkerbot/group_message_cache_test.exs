defmodule GptTalkerbot.GroupMessageCacheTest do
  use GptTalkerbot.DataCase

  import Ecto.Query

  alias GptTalkerbot.GroupMessageCache
  alias GptTalkerbot.Memory.GroupMessage

  @chat "-100999"

  defp insert_msg(content, opts) do
    {:ok, msg} =
      %GroupMessage{}
      |> GroupMessage.changeset(%{
        chat_id: Keyword.get(opts, :chat, @chat),
        sender_name: Keyword.get(opts, :sender, "Fulano"),
        content: content
      })
      |> Repo.insert()

    set =
      []
      |> maybe_set(:inserted_at, opts[:inserted_at])
      |> maybe_set(:processed_at, opts[:processed_at])

    unless set == [] do
      GroupMessage |> where([g], g.id == ^msg.id) |> Repo.update_all(set: set)
    end

    msg
  end

  defp maybe_set(set, _key, nil), do: set
  defp maybe_set(set, key, value), do: [{key, value} | set]

  defp hours_ago(h), do: NaiveDateTime.add(NaiveDateTime.utc_now(), -h * 3600)

  describe "messages_since/2" do
    test "traz só a janela pedida, em ordem cronológica, incluindo as já resumidas" do
      insert_msg("velha, fora da janela", inserted_at: hours_ago(26))
      insert_msg("resumida mas de hoje", inserted_at: hours_ago(5), processed_at: DateTime.utc_now())
      insert_msg("recente", inserted_at: hours_ago(1))

      cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600)

      contents = GroupMessageCache.messages_since(@chat, cutoff) |> Enum.map(& &1.content)

      assert contents == ["resumida mas de hoje", "recente"]
    end

    test "não vaza mensagens de outros chats" do
      insert_msg("do outro grupo", chat: "-100000", inserted_at: hours_ago(1))
      insert_msg("deste grupo", inserted_at: hours_ago(1))

      cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600)

      contents = GroupMessageCache.messages_since(@chat, cutoff) |> Enum.map(& &1.content)

      assert contents == ["deste grupo"]
    end

    test "sem mensagens na janela retorna lista vazia" do
      insert_msg("antiga", inserted_at: hours_ago(30))

      cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600)

      assert GroupMessageCache.messages_since(@chat, cutoff) == []
    end
  end

  describe "format_transcript/1" do
    test "formata cada mensagem como [HH:MM] Nome: texto" do
      messages = [
        %{sender_name: "Fulano", content: "bom dia", inserted_at: ~N[2026-07-20 09:05:30]},
        %{sender_name: "Beltrana", content: "cadê o café", inserted_at: ~N[2026-07-20 09:07:00]}
      ]

      assert GroupMessageCache.format_transcript(messages) ==
               "[09:05] Fulano: bom dia\n[09:07] Beltrana: cadê o café"
    end

    test "lista vazia vira string vazia" do
      assert GroupMessageCache.format_transcript([]) == ""
    end
  end

  describe "purge_older_than/1" do
    test "apaga o que passou da retenção e preserva o resto, mesmo já resumido" do
      insert_msg("expirada", inserted_at: hours_ago(50))
      insert_msg("no limite recente", inserted_at: hours_ago(10), processed_at: DateTime.utc_now())

      cutoff = DateTime.add(DateTime.utc_now(), -48 * 3600)

      assert GroupMessageCache.purge_older_than(cutoff) == 1

      remaining = Repo.all(GroupMessage) |> Enum.map(& &1.content)
      assert remaining == ["no limite recente"]
    end
  end
end
