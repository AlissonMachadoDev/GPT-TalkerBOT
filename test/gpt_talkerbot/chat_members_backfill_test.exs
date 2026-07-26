Code.require_file("priv/repo/migrations/20260725000002_backfill_chat_member_last_message_at.exs")

defmodule GptTalkerbot.ChatMembersBackfillTest do
  @moduledoc """
  O backfill roda uma vez em produção e é SQL cru, sem changeset nem tipo do
  Ecto para segurar erro. O teste executa o mesmo statement da migration.
  """

  use GptTalkerbot.DataCase

  alias GptTalkerbot.ChatMembers.ChatMember
  alias GptTalkerbot.Memory.GroupMessage
  alias GptTalkerbot.Repo.Migrations.BackfillChatMemberLastMessageAt

  @chat_id "-100555"
  @outro_chat "-100999"
  @counter_start ~N[2026-07-15 00:00:00]

  defp member(attrs) do
    %ChatMember{chat_id: @chat_id, status: "active", message_count: 10}
    |> struct(attrs)
    |> Repo.insert!()
  end

  defp message(attrs) do
    %GroupMessage{chat_id: @chat_id, content: "oi"}
    |> struct(attrs)
    |> Repo.insert!()
  end

  defp backfill do
    Repo.query!(BackfillChatMemberLastMessageAt.sql())
    Repo.query!(BackfillChatMemberLastMessageAt.counter_sql())
  end

  defp reload(member), do: Repo.get!(ChatMember, member.id)

  test "preenche com a mensagem mais recente da pessoa" do
    m = member(%{user_id: "1", first_name: "Marcela"})
    message(%{sender_name: "Marcela", inserted_at: ~N[2026-07-24 10:00:00]})
    message(%{sender_name: "Marcela", inserted_at: ~N[2026-07-25 18:00:00]})

    backfill()

    assert DateTime.to_naive(reload(m).last_message_at) == ~N[2026-07-25 18:00:00]
  end

  test "quem tem contador mas não aparece nas 48h cai no limite inferior" do
    m = member(%{user_id: "2", first_name: "Semanal", message_count: 40})

    backfill()

    assert DateTime.to_naive(reload(m).last_message_at) == @counter_start
  end

  test "quem nunca falou continua sem marca e fora do páreo" do
    m = member(%{user_id: "7", first_name: "AdminMudo", message_count: 0})

    backfill()

    assert reload(m).last_message_at == nil
  end

  test "xarás no mesmo chat não recebem a atividade um do outro" do
    a = member(%{user_id: "3", first_name: "Ana"})
    b = member(%{user_id: "4", first_name: "Ana"})
    message(%{sender_name: "Ana", inserted_at: ~N[2026-07-25 12:00:00]})

    backfill()

    assert DateTime.to_naive(reload(a).last_message_at) == @counter_start
    assert DateTime.to_naive(reload(b).last_message_at) == @counter_start
  end

  test "mensagem de outro chat não conta para o membro daqui" do
    m = member(%{user_id: "5", first_name: "Beto"})
    message(%{chat_id: @outro_chat, sender_name: "Beto", inserted_at: ~N[2026-07-25 12:00:00]})

    backfill()

    assert DateTime.to_naive(reload(m).last_message_at) == @counter_start
  end

  test "não sobrescreve marca já registrada pelo rastreamento normal" do
    ja_rastreado = ~U[2026-07-25 20:00:00Z]
    m = member(%{user_id: "6", first_name: "Zeca", last_message_at: ja_rastreado})
    message(%{sender_name: "Zeca", inserted_at: ~N[2026-07-20 09:00:00]})

    backfill()

    assert reload(m).last_message_at == ja_rastreado
  end
end
