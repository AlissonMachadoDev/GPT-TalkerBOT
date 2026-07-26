defmodule GptTalkerbot.Repo.Migrations.BackfillChatMemberLastMessageAt do
  use Ecto.Migration

  # Sem isso o chat inteiro começa com last_message_at NULL, ninguém é
  # frequente, e a primeira pessoa que falar depois do deploy vira a única
  # sorteável do grupo.
  #
  # group_messages guarda o primeiro nome do remetente, não o user_id, então
  # o casamento é por nome dentro do chat — e nome repetido no grupo fica de
  # fora, que é melhor do que dar a atividade ao xará errado. A retenção é de
  # 48h, então o backfill cobre justamente quem andou falando.
  # Data em que a coluna message_count entrou (migration 20260715000001), sem
  # backfill: contador acima de zero só pode ter sido acumulado depois dela
  @counter_start "2026-07-15 00:00:00"

  def up do
    execute(sql())
    execute(counter_sql())
  end

  # Para quem não apareceu nas 48h de group_messages sobra o que o contador
  # prova: falou alguma vez desde @counter_start. Grava esse limite inferior em
  # vez de "agora" — é o que se sabe de fato, e vence mais cedo se a pessoa não
  # voltar a falar. Sem isso, quem conversa toda semana mas não falou nos
  # últimos dois dias começaria fora do páreo.
  def counter_sql do
    """
    UPDATE chat_members
    SET last_message_at = '#{@counter_start}'
    WHERE last_message_at IS NULL
      AND message_count > 0
    """
  end

  # Exposto para o teste rodar exatamente o mesmo statement que vai para o banco
  def sql do
    """
    UPDATE chat_members cm
    SET last_message_at = src.last_at
    FROM (
      SELECT chat_id, sender_name, MAX(inserted_at) AS last_at
      FROM group_messages
      GROUP BY chat_id, sender_name
    ) src
    WHERE cm.chat_id = src.chat_id
      AND cm.first_name = src.sender_name
      AND cm.last_message_at IS NULL
      AND (
        SELECT COUNT(*)
        FROM chat_members dup
        WHERE dup.chat_id = cm.chat_id AND dup.first_name = cm.first_name
      ) = 1
    """
  end

  # Reverter apagaria também a atividade legítima registrada depois do deploy
  def down, do: :ok
end
