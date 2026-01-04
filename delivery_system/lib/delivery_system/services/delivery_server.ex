defmodule DeliverySystem.Services.DeliveryServer do
  @moduledoc """
  Implementação do servidor de entregas para motoristas.
  """
  use GRPC.Server, service: Delivery.DeliveryService.Service
  require Logger

  alias Delivery.{
    DriverRequest,
    DeliveryOrder,
    AcceptRequest,
    AcceptResponse,
    LocationSummary
  }

  @doc """
  Server Streaming: Motorista recebe stream de pedidos disponíveis
  """
  def stream_available_orders(%DriverRequest{driver_id: driver_id}, materializer) do
    Logger.info("Motorista #{driver_id} conectado para receber pedidos")

    # Stream infinito que envia novos pedidos quando disponíveis
    Stream.resource(
      fn -> {driver_id, 0} end,
      fn {driver_id, count} ->
        # Simula espera por novos pedidos
        Process.sleep(:rand.uniform(3000) + 2000)

        order = %DeliveryOrder{
          order_id: "ORD-#{count + 1}",
          restaurant_name: random_restaurant(),
          restaurant_address: "Rua A, 123",
          delivery_address: "Rua B, 456",
          distance_km: :rand.uniform(10) * 1.0,
          estimated_payment: 10.0 + :rand.uniform(20)
        }

        {[order], {driver_id, count + 1}}
      end,
      fn _ -> :ok end
    )
    |> GRPC.Stream.from(max_demand: 3)
    |> GRPC.Stream.effect(fn order ->
      Logger.info("Novo pedido disponível para #{driver_id}: #{order.order_id}")
    end)
    |> GRPC.Stream.run_with(materializer)
  end

  @doc """
  Unary: Motorista aceita um pedido
  """
  def accept_order(request, materializer) do
    GRPC.Stream.unary(request, materializer: materializer)
    |> GRPC.Stream.map(fn %AcceptRequest{driver_id: driver_id, order_id: order_id} ->
      Logger.info("🏍️  MOTORISTA #{driver_id}: Aceitou o pedido #{order_id}")

      # Verifica se pedido ainda está disponível
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
  Client Streaming: Motorista envia stream de atualizações de localização
  """
  def update_location(location_stream, _materializer) do
    # Processa o stream usando a API GRPC.Stream com reduce porém demonstrando o uso da função to_flow.
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
          # Calcula distância desde última atualização
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

  defp random_restaurant do
    restaurants = [
      "Pizzaria Bella",
      "Burguer King",
      "Sushi House",
      "Taco Bell",
      "McDonald's"
    ]

    Enum.random(restaurants)
  end

  defp pedido_disponivel?(_order_id) do
    # Simula 80% de chance de pedido estar disponível
    :rand.uniform(10) <= 8
  end

  defp calculate_distance(loc1, loc2) do
    # Fórmula simplificada de Haversine
    lat_diff = abs(loc1.latitude - loc2.latitude)
    lng_diff = abs(loc1.longitude - loc2.longitude)
    :math.sqrt(lat_diff * lat_diff + lng_diff * lng_diff) * 111.0
  end
end
