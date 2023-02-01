defmodule GptTalkerbot.RMQPublisher do
  @moduledoc """
  Provides the interface to publish events in te pubsub and manages supported
  events
  """
  alias __MODULE__
  require Logger
  @behaviour GenRMQ.Publisher

  @rmq_uri "amqp://rabbitmq:rabbitmq@localhost:5672"
  @bot_exchange "bot_analytics"
  @messages_queue "bot_messages"

  def start_link() do
    GenRMQ.Publisher.start_link(RMQPublisher, name: RMQPublisher)
  end

  def publish_message(message) do
    message = Jason.encode!(%{message: message})
    GenRMQ.Publisher.publish(RMQPublisher, message, @messages_queue)
  end

  def init do
    create_rmq_resources()
    [
      connection: @rmq_uri,
      exchange: @bot_exchange
    ]
  end

  def create_rmq_resources do

    # Setup RabbitMQ connection
    {:ok, connection} = AMQP.Connection.open(@rmq_uri)
    {:ok, channel} = AMQP.Channel.open(connection)

    # Create exchange
    AMQP.Exchange.declare(channel, @bot_exchange, :topic, durable: true)

    # Create queues
    AMQP.Queue.declare(channel, @messages_queue, durable: true)

    # Bind queues to exchange
    AMQP.Queue.bind(channel, @messages_queue, @bot_exchange, routing_key: @messages_queue)

    # Close the channel as it is no longer needed
    # GenRMQ will manage its own channel
    AMQP.Channel.close(channel)
  end
end
