defmodule DeliverySystem.Services.DeliveryServer do
  @moduledoc """
  Delivery server implementation for drivers.
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
  Uses GenStage producer with join_with to emit orders proactively.
  """
  def stream_available_orders(%DriverRequest{driver_id: driver_id}, materializer) do
    Logger.info("Motorista #{driver_id} conectado para receber pedidos")

    # Empty stream from request, join with producer to emit orders
    []
    |> GRPC.Stream.from(join_with: AvailableOrdersProducer, max_demand: 2)
    |> GRPC.Stream.map(fn
      # Orders from producer (via join_with)
      {:available_order, order} ->
        Logger.info("Novo pedido disponível para #{driver_id}: #{order.order_id}")
        order
    end)
    |> GRPC.Stream.run_with(materializer)
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
        %{driver_id: nil, count: 0, total_distance: 0.0, last_location: nil},
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
            count: acc.count + 1,
            total_distance: acc.total_distance + distance,
            last_location: update.location
          }
        end
      )

    Logger.info(
      "✅ #{result.count} atualizações recebidas - Distância: #{Float.round(result.total_distance, 2)} km"
    )

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
