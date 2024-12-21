defmodule GptTalkerbot.BotProcessor do
  use Broadway

  alias Broadway.Message, as: BroadwayMessage
  alias GptTalkerbot.Telegram

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          BroadwayRabbitMQ.Producer,
          queue: "bot_messages",
          on_failure: :reject_and_requeue,
          connection: [
            username: "rabbitmq",
            password: "rabbitmq"
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
    {:ok, given_message} =
      Jason.decode!(data)
      |> then(&Telegram.rebuild_message(&1["message"]))

    Telegram.process_message(given_message)

    message
  end
end
