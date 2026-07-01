defmodule GptTalkerbot.BotProcessor do
  use Broadway

  require Logger

  alias Broadway.Message, as: BroadwayMessage
  alias GptTalkerbot.Telegram

  def start_link(_opts) do
    rmq = Application.get_env(:gpt_talkerbot, :rabbitmq, [])

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          BroadwayRabbitMQ.Producer,
          queue: "bot_messages",
          # Nunca devolver para a fila: reprocessar significa pagar outra
          # completion de LLM a cada volta do loop
          on_failure: :reject,
          connection: [
            host: rmq[:host] || "localhost",
            username: rmq[:username],
            password: rmq[:password]
          ]
        },
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: 20
        ]
      ]
    )
  end

  @impl true
  def handle_message(_processor, %BroadwayMessage{data: data} = message, _context) do
    with {:ok, decoded} <- Jason.decode(data),
         {:ok, given_message} <- Telegram.build_message(decoded["message"]) do
      Telegram.process_message(given_message)
    else
      # Mensagem inválida nunca vai ficar válida: descarta em vez de
      # deixar o crash + requeue reciclá-la para sempre
      error ->
        Logger.warning("BotProcessor: discarding invalid message: #{inspect(error)}")
    end

    message
  rescue
    # Crash em qualquer ponto do processamento (envio ao Telegram, banco,
    # etc.) descarta a mensagem com log — nunca reprocessa, porque a
    # completion de LLM já foi paga e seria paga de novo a cada retry
    e ->
      Logger.error(
        "BotProcessor: crashed processing message, discarding: " <>
          Exception.format(:error, e, __STACKTRACE__)
      )

      message
  end
end
