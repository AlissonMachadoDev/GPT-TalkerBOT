defmodule GptTalkerbot.Memory.ForgetByContentTest do
  use GptTalkerbot.DataCase

  alias GptTalkerbot.Memory
  alias GptTalkerbot.Memory.ConversationMessage

  @chat_id "-100777"
  @user_id "111"

  test "apaga todas as ocorrências do conteúdo, em qualquer role" do
    Memory.save_exchange(@chat_id, @user_id, "pergunta boa", "resposta podre xyz")
    Memory.save_exchange(@chat_id, @user_id, "pergunta boa", "resposta podre xyz")
    Memory.save_exchange(@chat_id, @user_id, "outra pergunta", "resposta sã")

    assert Memory.forget_by_content(@chat_id, "resposta podre xyz") == 2

    remaining = Repo.all(ConversationMessage) |> Enum.map(& &1.content) |> Enum.sort()
    assert remaining == ["outra pergunta", "pergunta boa", "pergunta boa", "resposta sã"]
  end

  test "compara ignorando as tags HTML que o Telegram remove do texto exibido" do
    Memory.save_exchange(@chat_id, @user_id, "oi", "<i>*fusível queimado*</i> deu ruim")

    assert Memory.forget_by_content(@chat_id, "*fusível queimado* deu ruim") == 1
  end

  test "não mexe em outros chats" do
    Memory.save_exchange(@chat_id, @user_id, "oi", "resposta")
    Memory.save_exchange("-100888", @user_id, "oi", "resposta")

    assert Memory.forget_by_content(@chat_id, "resposta") == 1
    assert Repo.aggregate(ConversationMessage, :count) == 3
  end

  test "conteúdo inexistente retorna zero sem apagar nada" do
    Memory.save_exchange(@chat_id, @user_id, "oi", "resposta")

    assert Memory.forget_by_content(@chat_id, "nunca dita") == 0
    assert Repo.aggregate(ConversationMessage, :count) == 2
  end
end
