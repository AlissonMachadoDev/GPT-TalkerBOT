defmodule GptTalkerbot.MemorySessionTest do
  use ExUnit.Case, async: true

  alias GptTalkerbot.Memory

  defp msg(content, inserted_at) do
    %{role: "user", content: content, inserted_at: inserted_at}
  end

  test "sem gap mantém todas as mensagens" do
    messages = [
      msg("a", ~N[2026-07-01 10:00:00]),
      msg("b", ~N[2026-07-01 10:10:00]),
      msg("c", ~N[2026-07-01 10:20:00])
    ]

    assert Memory.trim_to_last_session(messages) == [
             %{role: "user", content: "a"},
             %{role: "user", content: "b"},
             %{role: "user", content: "c"}
           ]
  end

  test "gap maior que a sessão descarta a conversa anterior" do
    messages = [
      msg("ontem", ~N[2026-07-01 08:00:00]),
      # gap de 2h (> 60min de sessão)
      msg("agora 1", ~N[2026-07-01 10:00:00]),
      msg("agora 2", ~N[2026-07-01 10:05:00])
    ]

    assert Memory.trim_to_last_session(messages) == [
             %{role: "user", content: "agora 1"},
             %{role: "user", content: "agora 2"}
           ]
  end

  test "usa apenas o último gap quando há vários" do
    messages = [
      msg("a", ~N[2026-07-01 06:00:00]),
      msg("b", ~N[2026-07-01 08:00:00]),
      msg("c", ~N[2026-07-01 10:00:00])
    ]

    assert Memory.trim_to_last_session(messages) == [%{role: "user", content: "c"}]
  end

  test "lista vazia" do
    assert Memory.trim_to_last_session([]) == []
  end
end
