defmodule DeliverySystem.Clients.Driver do
  @moduledoc """
  Cliente para simular um motorista de entrega.
  """
  require Logger

  alias Delivery.{
    DriverRequest,
    Location,
    AcceptRequest,
    LocationUpdate
  }

  @doc """
  Exemplo de Server Streaming: Motorista recebe pedidos disponíveis
  """
  def listen_for_orders(channel, driver_id, max_orders \\ 3) do
    request = %DriverRequest{
      driver_id: driver_id,
      current_location: %Location{
        latitude: -19.9191,
        longitude: -43.9387
      }
    }

    Logger.info("🚗 Motorista #{driver_id} aguardando pedidos...")

    {:ok, stream} = Delivery.DeliveryService.Stub.stream_available_orders(channel, request)

    stream
    |> Stream.take(max_orders)
    |> Enum.each(fn order ->
      Logger.info("📦 Novo pedido disponível!")
      Logger.info("   ID: #{order.order_id}")
      Logger.info("   Restaurante: #{order.restaurant_name}")
      Logger.info("   Distância: #{order.distance_km}km")
      Logger.info("   Pagamento: R$ #{order.estimated_payment}")
    end)

    Logger.info("✅ Stream de pedidos finalizado")
  end

  @doc """
  Exemplo de Unary RPC: Motorista aceita um pedido
  """
  def accept_order(channel, driver_id, order_id) do
    request = %AcceptRequest{
      driver_id: driver_id,
      order_id: order_id
    }

    case Delivery.DeliveryService.Stub.accept_order(channel, request) do
      {:ok, response} ->
        if response.success do
          Logger.info("✅ Pedido #{order_id} aceito!")
          Logger.info("   Pagamento: R$ #{response.order.estimated_payment}")
        else
          Logger.warning("⚠️  #{response.message}")
        end

        {:ok, response}

      {:error, error} ->
        Logger.error("❌ Erro ao aceitar pedido: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Exemplo de Client Streaming: Motorista envia atualizações de localização
  """
  def send_location_updates(channel, driver_id, order_id, num_updates \\ 5) do
    Logger.info("📍 Motorista #{driver_id} enviando atualizações de localização...")

    # Stream de atualizações de localização
    updates =
      Stream.unfold({-19.9191, -43.9387, 1}, fn {lat, lng, count} ->
        if count > num_updates do
          nil
        else
          Process.sleep(1000)

          # Simula movimento
          new_lat = lat + (:rand.uniform(100) - 50) / 10000.0
          new_lng = lng + (:rand.uniform(100) - 50) / 10000.0

          update = %LocationUpdate{
            driver_id: driver_id,
            order_id: order_id,
            location: %Location{
              latitude: new_lat,
              longitude: new_lng
            },
            timestamp: System.system_time(:second)
          }

          Logger.info(
            "📍 Atualização #{count}: #{Float.round(new_lat, 4)}, #{Float.round(new_lng, 4)}"
          )

          {update, {new_lat, new_lng, count + 1}}
        end
      end)

    {:ok, summary} = Delivery.DeliveryService.Stub.update_location(channel, updates)

    Logger.info("✅ Resumo das atualizações:")
    Logger.info("   Total de atualizações: #{summary.updates_received}")
    Logger.info("   Distância percorrida: #{summary.total_distance_km}km")

    {:ok, summary}
  end
end
