defmodule DeliverySystem.Services.OrderServer do
  @moduledoc """
  OrderService implementation demonstrating all 4 gRPC streaming types.

  This service handles the complete order lifecycle from the customer's perspective,
  showcasing different streaming patterns available in gRPC:

  ## Service Overview

  The OrderService is the main interface for customers to:
  - Create new orders (Unary RPC)
  - Track order status in real-time (Server Streaming)
  - Have restaurants prepare multiple items (Client Streaming)
  - Engage in bidirectional chat with the system (Bidirectional Streaming)

  ## Expected Interaction Flow

  1. **Create Order** (`create_order/2`) - Unary RPC
     - Customer sends a single order request with items
     - Server generates order_id and returns confirmation
     - Simple request-response pattern

  2. **Order Chat** (`order_chat/2`) - Bidirectional Streaming
     - Customer can send multiple messages about their order
     - System responds to each message automatically
     - System can also send proactive updates (using GenStage producer with `join_with`)
     - Demonstrates true bidirectional communication

  3. **Prepare Order** (`prepare_order/2`) - Client Streaming
     - Restaurant sends multiple items as they are being prepared
     - Each item is logged and processed
     - Server returns a final preparation summary when stream ends
     - Demonstrates aggregating multiple client messages

  4. **Track Order** (`track_order/2`) - Server Streaming
     - Customer requests to track a specific order
     - Server sends multiple status updates over time
     - Updates include: created → preparing → ready → picked_up → on_the_way → delivered
     - Demonstrates server pushing multiple responses for a single request

  ## Technical Implementation

  - Uses `GRPC.Stream` API for all operations
  - Server Streaming: Built with `Stream.iterate` and controlled delays
  - Client Streaming: Uses `GRPC.Stream.from/2` with `Flow.from_enumerable/1` for backpressure
  - Bidirectional Streaming: Combines `join_with: SystemMessageProducer` to merge client messages with proactive system messages
  - All operations are logged with indicators for visual feedback

  ## Example Usage

      # Connect to the service
      {:ok, channel} = GRPC.Stub.connect("localhost:50051")

      # 1. Create order (Unary)
      request = %OrderRequest{customer_id: "C001", items: ["Pizza"]}
      {:ok, response} = Delivery.OrderService.Stub.create_order(channel, request)

      # 2. Track order (Server Streaming)
      track_req = %TrackRequest{order_id: response.order_id}
      {:ok, stream} = Delivery.OrderService.Stub.track_order(channel, track_req)
      Enum.each(stream, fn {:ok, status} -> IO.inspect(status) end)

      # 3. Prepare order (Client Streaming)
      stream = Delivery.OrderService.Stub.prepare_order(channel)
      GRPC.Stub.send_request(stream, %OrderItem{order_id: "123", item_name: "Pizza"})
      GRPC.Stub.end_stream(stream)
      {:ok, summary} = GRPC.Stub.recv(stream)

      # 4. Chat (Bidirectional)
      chat_stream = Delivery.OrderService.Stub.order_chat(channel)
      GRPC.Stub.send_request(chat_stream, %ChatMessage{order_id: "123", message: "Hello"})
      {:ok, responses} = GRPC.Stub.recv(chat_stream)
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
    |> GRPC.Stream.map(fn %OrderRequest{} = req -> {generate_order_id(), req} end)
    |> GRPC.Stream.effect(fn {order_id, %OrderRequest{} = req} ->
      Logger.info("👤 CLIENTE #{req.customer_id}: Criou pedido #{order_id}")

      # Save order to persistent store
      DeliverySystem.OrderStore.save_order(order_id, %{
        customer_id: req.customer_id,
        items: req.items,
        status: :created
      })
    end)
    |> GRPC.Stream.map(fn {order_id, %OrderRequest{} = _req} ->
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

      # Update order status in persistent store
      DeliverySystem.OrderStore.update_status(order_id, status)

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

    # Update order status to ready
    if result.order_id && result.order_id != "unknown" do
      DeliverySystem.OrderStore.update_status(result.order_id, :ready)
    end

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

  defp status_message(:created), do: "Pedido recebido"
  defp status_message(:preparing), do: "Restaurante está preparando"
  defp status_message(:ready), do: "Pedido pronto para retirada"
  defp status_message(:picked_up), do: "Entregador coletou o pedido"
  defp status_message(:on_the_way), do: "Entregador a caminho"
  defp status_message(:delivered), do: "Pedido entregue!"
end
