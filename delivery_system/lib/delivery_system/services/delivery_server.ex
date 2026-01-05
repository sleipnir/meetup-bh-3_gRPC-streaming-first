defmodule DeliverySystem.Services.DeliveryServer do
  @moduledoc """
  DeliveryService implementation for driver operations and order fulfillment.

  This service handles the delivery lifecycle from the driver's perspective,
  demonstrating different streaming patterns for driver-system interactions.

  ## Service Overview

  The DeliveryService is the interface for drivers to:
  - Listen for available orders in real-time (Server Streaming)
  - Accept orders they want to deliver (Unary RPC)
  - Send location updates during delivery (Client Streaming)

  ## Expected Interaction Flow

  1. **Stream Available Orders** (`stream_available_orders/2`) - Server Streaming
     - Driver connects and starts listening for new orders
     - Server continuously pushes available orders as they become ready
     - Uses GenStage producer with `join_with` to emit orders on demand
     - Demonstrates proactive server push with backpressure support
     - Driver can set `max_demand` to control how many orders to receive

  2. **Accept Order** (`accept_order/2`) - Unary RPC
     - Driver accepts a specific order by order_id
     - Server validates availability and assigns order to driver
     - Returns success confirmation with delivery details
     - Simple request-response pattern

  3. **Update Location** (`update_location/2`) - Client Streaming
     - Driver sends multiple GPS coordinates during delivery
     - Each location update is logged with timestamp
     - Server calculates total distance traveled
     - Returns final delivery summary when stream ends
     - Demonstrates aggregating multiple client messages

  ## Technical Implementation

  - Uses `GRPC.Stream` API for all operations
  - Server Streaming: Implemented with `join_with: AvailableOrdersProducer`
    - Producer generates orders on demand via `handle_demand`
    - Empty input stream `[]` is joined with producer output
    - Pattern: `[] |> GRPC.Stream.from(join_with: Producer, max_demand: N)`
  - Client Streaming: Uses `GRPC.Stream.from/2` with Flow for backpressure
  - Haversine formula for distance calculation between coordinates
  - All operations logged with emoji indicators (🏍️ for driver, 🖥️ for system)

  ## Example Usage

      # Connect to the service
      {:ok, channel} = GRPC.Stub.connect("localhost:50051")

      # 1. Listen for orders (Server Streaming)
      request = %DriverRequest{driver_id: "D042"}
      {:ok, stream} = Delivery.DeliveryService.Stub.stream_available_orders(channel, request)
      Enum.each(stream, fn {:ok, order} ->
        IO.puts("New order: \#{order.order_id}")
      end)

      # 2. Accept order (Unary)
      accept_req = %AcceptRequest{driver_id: "D042", order_id: "ORDER-123"}
      {:ok, response} = Delivery.DeliveryService.Stub.accept_order(channel, accept_req)

      # 3. Update location (Client Streaming)
      stream = Delivery.DeliveryService.Stub.update_location(channel)
      GRPC.Stub.send_request(stream, %LocationUpdate{
        driver_id: "D042",
        order_id: "ORDER-123",
        location: %Location{latitude: -23.5505, longitude: -46.6333}
      })
      GRPC.Stub.end_stream(stream)
      {:ok, summary} = GRPC.Stub.recv(stream)

  ## Integration with OrderService

  This service works in conjunction with OrderService:
  1. Customer creates order via OrderService.create_order
  2. Order becomes available in DeliveryService.stream_available_orders
  3. Driver accepts order via DeliveryService.accept_order
  4. Driver delivers and sends location updates via DeliveryService.update_location
  5. Customer tracks progress via OrderService.track_order
  """
  use GRPC.Server, service: Delivery.DeliveryService.Service
  require Logger

  alias Delivery.DriverRequest
  alias Delivery.DeliveryOrder
  alias Delivery.AcceptRequest
  alias Delivery.AcceptResponse
  alias Delivery.LocationSummary
  alias DeliverySystem.Producers.AvailableOrdersProducer

  @doc """
  Server Streaming: Driver receives stream of available orders
  Uses GenStage producer to fetch orders on demand.
  Each driver gets a single order when they connect.
  """
  def stream_available_orders(%DriverRequest{driver_id: driver_id}, materializer) do
    Logger.info("Motorista #{driver_id} conectado para receber pedidos")

    # Instead of join_with (which creates multiple subscriptions),
    # we'll request orders directly from the producer and emit as a stream
    case AvailableOrdersProducer.request_order(driver_id) do
      {:ok, delivery_order} ->
        Logger.info("Novo pedido disponível para #{driver_id}: #{delivery_order.order_id}")

        # Emit single order as a stream
        [delivery_order]
        |> GRPC.Stream.from()
        |> GRPC.Stream.run_with(materializer)

      {:error, :no_orders_available} ->
        Logger.info("Nenhum pedido disponível para #{driver_id}")

        # Emit empty stream
        []
        |> GRPC.Stream.from()
        |> GRPC.Stream.run_with(materializer)
    end
  end

  @doc """
  Unary: Driver accepts an order
  """
  def accept_order(request, materializer) do
    GRPC.Stream.unary(request, materializer: materializer)
    |> GRPC.Stream.map(fn %AcceptRequest{driver_id: driver_id, order_id: order_id} ->
      Logger.info("🏍️  MOTORISTA #{driver_id}: Aceitou o pedido #{order_id}")

      # Check if order is still available
      if pedido_disponivel?(order_id) do
        # Update order status to assigned/picked_up
        DeliverySystem.OrderStore.update_status(order_id, :picked_up)

        %AcceptResponse{
          success: true,
          message: "Pedido aceito com sucesso!",
          order: %DeliveryOrder{
            order_id: order_id,
            restaurant_name: "Restaurante X",
            restaurant_address: "Rua A, 123",
            delivery_address: "Rua B, 456",
            distance_km: 5.5,
            estimated_payment: 25.0
          }
        }
      else
        %AcceptResponse{
          success: false,
          message: "Pedido já foi aceito por outro motorista",
          order: nil
        }
      end
    end)
    |> GRPC.Stream.run()
  end

  @doc """
  Client Streaming: Driver sends stream of location updates
  """
  def update_location(location_stream, _materializer) do
    # Process stream using GRPC.Stream API with reduce but demonstrating the use of to_flow function.
    result =
      location_stream
      |> GRPC.Stream.from(max_demand: 10)
      |> GRPC.Stream.effect(fn update ->
        Logger.info(
          "🏍️  MOTORISTA #{update.driver_id}: Localização " <>
            "(#{Float.round(update.location.latitude, 4)}, #{Float.round(update.location.longitude, 4)})"
        )
      end)
      |> GRPC.Stream.to_flow()
      |> Enum.reduce(
        %{driver_id: nil, order_id: nil, count: 0, total_distance: 0.0, last_location: nil},
        fn update, acc ->
          # Calculate distance from last update
          distance =
            if acc.last_location do
              calculate_distance(acc.last_location, update.location)
            else
              0.0
            end

          %{
            driver_id: update.driver_id,
            order_id: update.order_id,
            count: acc.count + 1,
            total_distance: acc.total_distance + distance,
            last_location: update.location
          }
        end
      )

    Logger.info(
      "✅ #{result.count} atualizações recebidas - Distância: #{Float.round(result.total_distance, 2)} km"
    )

    # Mark order as delivered after location updates complete
    if result.order_id do
      DeliverySystem.OrderStore.update_status(result.order_id, :delivered)
    end

    %LocationSummary{
      driver_id: result.driver_id || "unknown",
      updates_received: result.count,
      total_distance_km: Float.round(result.total_distance, 2)
    }
  end

  defp pedido_disponivel?(_order_id) do
    # Simulate 80% chance of order being available
    :rand.uniform(10) <= 8
  end

  defp calculate_distance(loc1, loc2) do
    # Simplified Haversine formula
    lat_diff = abs(loc1.latitude - loc2.latitude)
    lng_diff = abs(loc1.longitude - loc2.longitude)
    :math.sqrt(lat_diff * lat_diff + lng_diff * lng_diff) * 111.0
  end
end
