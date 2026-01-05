defmodule DeliverySystem.Clients.Driver do
  @moduledoc """
  Client to simulate a delivery driver.
  """
  require Logger

  alias Delivery.DriverRequest
  alias Delivery.Location
  alias Delivery.AcceptRequest
  alias Delivery.LocationUpdate

  @doc """
  Server Streaming example: Driver receives available orders
  """
  def listen_for_orders(channel, driver_id, max_orders \\ 2) do
    request = %DriverRequest{
      driver_id: driver_id,
      current_location: %Location{
        latitude: -19.9191,
        longitude: -43.9387
      }
    }

    {:ok, stream} = Delivery.DeliveryService.Stub.stream_available_orders(channel, request)

    orders =
      stream
      |> Stream.take(max_orders)
      |> Enum.map(fn
        {:ok, order} ->
          IO.puts("   📦 Pedido disponível: #{order.order_id}")
          IO.puts("      🍴 #{order.restaurant_name}")

          IO.puts(
            "      📏 #{order.distance_km}km - R$ #{Float.round(order.estimated_payment, 2)}"
          )

          order

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    IO.puts("   ✅ #{length(orders)} pedido(s) recebido(s)")
    {:ok, orders}
  end

  @doc """
  Unary RPC example: Driver accepts an order
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
  Client Streaming example: Driver sends location updates
  """
  def send_location_updates(channel, driver_id, order_id, num_updates \\ 5) do
    # Predefined realistic locations for São Paulo delivery route
    route = [
      {-23.5505, -46.6333, "Saindo do restaurante"},
      {-23.5515, -46.6343, "Avenida Paulista"},
      {-23.5525, -46.6353, "Próximo ao destino"},
      {-23.5535, -46.6363, "Entrando na rua"},
      {-23.5545, -46.6373, "Chegou ao destino"}
    ]

    # Create enumerable of location updates
    updates =
      route
      |> Enum.take(num_updates)
      |> Enum.with_index(1)
      |> Enum.map(fn {{lat, lng, description}, count} ->
        if count > 1, do: Process.sleep(800)

        update = %LocationUpdate{
          driver_id: driver_id,
          order_id: order_id,
          location: %Location{
            latitude: lat,
            longitude: lng
          },
          timestamp: System.system_time(:second)
        }

        IO.puts("   📍 #{description}: (#{lat}, #{lng})")

        update
      end)

    {:ok, summary} = Delivery.DeliveryService.Stub.update_location(channel, updates)

    IO.puts(
      "   ✅ Entrega concluída! Distância total: #{Float.round(summary.total_distance_km, 2)} km"
    )

    {:ok, summary}
  end
end
