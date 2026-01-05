defmodule DeliverySystem.Services.OrderServer do
  @moduledoc """
  Order server implementation with examples of all streaming types.
  """
  use GRPC.Server, service: Delivery.OrderService.Service
  require Logger

  alias Delivery.ChatMessage
  alias Delivery.OrderRequest
  alias Delivery.OrderResponse
  alias Delivery.TrackRequest
  alias Delivery.OrderStatus
  alias Delivery.OrderItem
  alias Delivery.PreparationSummary
  alias DeliverySystem.Producers.SystemMessageProducer

  @doc """
  Unary RPC: Client creates a single order
  """
  def create_order(request, materializer) do
    GRPC.Stream.unary(request, materializer: materializer)
    |> GRPC.Stream.map(fn %OrderRequest{} = req ->
      order_id = generate_order_id()
      Logger.info("👤 CLIENTE #{req.customer_id}: Criou pedido #{order_id}")

      # Save order to state
      save_order(order_id, req)

      %OrderResponse{
        order_id: order_id,
        status: "created",
        estimated_time: 45.0
      }
    end)
    |> GRPC.Stream.run()
  end

  @doc """
  Server Streaming: Client tracks order status in real time
  Demonstrates how the server can send multiple updates
  """
  def track_order(%TrackRequest{order_id: order_id}, materializer) do
    Logger.info("👤 CLIENTE: Iniciou rastreamento do pedido #{order_id}")

    # Stream with delays between each status update
    # We use Stream.iterate + Stream.take to create a finite stream
    statuses = [:created, :preparing, :ready, :picked_up, :on_the_way, :delivered]

    Stream.iterate(0, &(&1 + 1))
    |> Stream.take(length(statuses))
    |> Stream.map(fn index ->
      # 2 second delay between each status (except the first)
      if index > 0, do: Process.sleep(2000)

      status = Enum.at(statuses, index)

      status_update = %OrderStatus{
        order_id: order_id,
        status: Atom.to_string(status),
        message: status_message(status),
        timestamp: System.system_time(:second)
      }

      Logger.info(
        "🖥️  SISTEMA: #{order_id} -> #{Atom.to_string(status) |> String.upcase()} - #{status_message(status)}"
      )

      status_update
    end)
    |> GRPC.Stream.from()
    |> GRPC.Stream.run_with(materializer)
  end

  @doc """
  Client Streaming: Restaurant sends order items one by one
  Demonstrates how to process a stream of messages from the client
  """
  def prepare_order(items_stream, _materializer) do
    result =
      items_stream
      |> GRPC.Stream.from()
      |> GRPC.Stream.effect(fn %OrderItem{} = item ->
        Logger.info("🍽️  RESTAURANTE: Preparando #{item.item_name} (x#{item.quantity})")
      end)
      |> GRPC.Stream.to_flow()
      |> Enum.reduce(
        %{order_id: nil, count: 0},
        fn %OrderItem{} = item, acc ->
          %{
            order_id: item.order_id,
            count: acc.count + item.quantity
          }
        end
      )

    # Return response directly
    %PreparationSummary{
      order_id: result.order_id || "unknown",
      total_items: result.count,
      status: "ready"
    }
  end

  @doc """
  Bidirectional Streaming: Chat between client and system
  Demonstrates unbounded bidirectional flow with a single GenStage producer.
  join_with merges the client stream with proactive messages from the producer.
  """
  def order_chat(messages_stream, materializer) do
    messages_stream
    |> GRPC.Stream.from(join_with: SystemMessageProducer, max_demand: 5)
    |> GRPC.Stream.effect(fn msg ->
      case msg do
        %ChatMessage{order_id: order_id, sender: sender, message: text} ->
          Logger.info("Chat [#{sender}] (#{order_id}): #{text}")

        {:system_message, order_id, text} ->
          Logger.info("Chat [sistema] (#{order_id}): #{text} (proativo)")
      end
    end)
    |> GRPC.Stream.map(fn
      # Client message - call producer and return response
      %ChatMessage{} = msg ->
        response = GenStage.call(SystemMessageProducer, {:client_message, msg})

        %ChatMessage{
          order_id: msg.order_id,
          sender: "sistema",
          message: response,
          timestamp: System.system_time(:second)
        }

      # Proactive message from producer (via join_with) - just convert
      {:system_message, order_id, text} ->
        %ChatMessage{
          order_id: order_id,
          sender: "sistema",
          message: text,
          timestamp: System.system_time(:second)
        }
    end)
    |> GRPC.Stream.run_with(materializer)
  end

  defp generate_order_id do
    "ORD-#{:rand.uniform(999_999)}"
  end

  defp save_order(order_id, _request) do
    # Here you would save to database/ETS
    Logger.debug("Pedido #{order_id} salvo")
  end

  defp status_message(:created), do: "Pedido recebido"
  defp status_message(:preparing), do: "Restaurante está preparando"
  defp status_message(:ready), do: "Pedido pronto para retirada"
  defp status_message(:picked_up), do: "Entregador coletou o pedido"
  defp status_message(:on_the_way), do: "Entregador a caminho"
  defp status_message(:delivered), do: "Pedido entregue!"
end
