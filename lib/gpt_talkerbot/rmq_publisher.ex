defmodule GptTalkerbot.RMQPublisher do
  @moduledoc """
  Provides the interface to publish events in te pubsub and manages supported
  events
  """
  alias __MODULE__
  require Logger
  use GenServer

  @rmq_uri "amqp://rabbitmq:rabbitmq@localhost:5672"
  @bot_exchange "bot_analytics"
  @messages_queue "bot_messages"

  def start_link(_opts) do
    GenServer.start_link(RMQPublisher, nil, name: RMQPublisher)
  end

  def publish_message(message) do
    GenServer.call(RMQPublisher, {:publish, message})
  end

  @impl true
  def init(_) do
    {:ok, conn} = AMQP.Connection.open(@rmq_uri)
    {:ok, channel} = AMQP.Channel.open(conn)

    setup_topology(channel)

    {:ok, %{conn: conn, channel: channel}}
  end

  def handle_call({:publish, message}, _from, state) do
    message_json = Jason.encode!(%{message: message})

    result =
      AMQP.Basic.publish(
        state.channel,
        @bot_exchange,
        @messages_queue,
        message_json,
        persistent: true
      )

    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    AMQP.Channel.close(state.channel)
    AMQP.Connection.close(state.conn)
  end

  defp setup_topology(channel) do
    AMQP.Exchange.declare(channel, @bot_exchange, :topic, durable: true)
    AMQP.Queue.declare(channel, @messages_queue, durable: true)
    AMQP.Queue.bind(channel, @messages_queue, @bot_exchange, routing_key: @messages_queue)
  end
end
