defmodule DeliverySystem.Clients.Customer do
  @moduledoc """
  Cliente para simular um cliente fazendo pedidos.
  """
  require Logger

  alias Delivery.{
    OrderRequest,
    TrackRequest,
    ChatMessage
  }

  @doc """
  Exemplo de Unary RPC: Cliente faz um pedido
  """
  def create_order(channel, customer_id, items) do
    request = %OrderRequest{
      customer_id: customer_id,
      restaurant_id: "REST-001",
      items: items,
      delivery_address: "Rua das Flores, 123"
    }

    case Delivery.OrderService.Stub.create_order(channel, request) do
      {:ok, response} ->
        Logger.info("✅ Pedido criado: #{response.order_id}")
        Logger.info("   Status: #{response.status}")
        Logger.info("   Tempo estimado: #{response.estimated_time} min")
        {:ok, response}

      {:error, error} ->
        Logger.error("❌ Erro ao criar pedido: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Exemplo de Server Streaming: Cliente rastreia pedido em tempo real
  """
  def track_order(channel, order_id) do
    request = %TrackRequest{order_id: order_id}

    {:ok, stream} = Delivery.OrderService.Stub.track_order(channel, request)

    stream
    |> Enum.each(fn
      {:ok, status} ->
        Logger.info("   📦 #{String.upcase(status.status)}: #{status.message}")

      {:error, reason} ->
        Logger.error("   ❌ Erro: #{inspect(reason)}")
    end)

    Logger.info("   ✅ Pedido entregue!")
  end

  @doc """
  Exemplo de Bidirectional Streaming: Chat com entregador
  """
  def start_chat(channel, order_id) do
    Logger.info("💬 Iniciando chat para pedido #{order_id}")

    # Stream de mensagens do cliente
    messages =
      Stream.unfold(1, fn count ->
        if count > 3 do
          nil
        else
          Process.sleep(2000)

          msg = %ChatMessage{
            order_id: order_id,
            sender: "customer",
            message: "Mensagem #{count} do cliente",
            timestamp: System.system_time(:second)
          }

          {msg, count + 1}
        end
      end)

    {:ok, response_stream} = Delivery.OrderService.Stub.order_chat(channel, messages)

    response_stream
    |> Enum.each(fn msg ->
      Logger.info("📨 [#{msg.sender}]: #{msg.message}")
    end)

    Logger.info("💬 Chat finalizado")
  end
end
