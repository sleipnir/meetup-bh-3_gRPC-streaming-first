defmodule DeliverySystem.Services.OrderServer do
  @moduledoc """
  Implementação do servidor de pedidos com exemplos de todos os tipos de streaming.
  """
  use GRPC.Server, service: Delivery.OrderService.Service
  require Logger

  alias Delivery.{
    OrderRequest,
    OrderResponse,
    TrackRequest,
    OrderStatus,
    OrderItem,
    PreparationSummary,
    ChatMessage
  }

  alias DeliverySystem.SystemMessageProducer

  @doc """
  Unary RPC: Cliente faz um pedido único
  """
  def create_order(request, materializer) do
    GRPC.Stream.unary(request, materializer: materializer)
    |> GRPC.Stream.map(fn %OrderRequest{} = req ->
      order_id = generate_order_id()
      Logger.info("👤 CLIENTE #{req.customer_id}: Criou pedido #{order_id}")

      # Salva o pedido no estado
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
  Server Streaming: Cliente acompanha status do pedido em tempo real
  Demonstra como o servidor pode enviar múltiplas atualizações
  """
  def track_order(%TrackRequest{order_id: order_id}, materializer) do
    Logger.info("👤 CLIENTE: Iniciou rastreamento do pedido #{order_id}")

    # Stream com delays entre cada atualização de status
    # Usamos Stream.iterate + Stream.take para criar um stream finito
    statuses = [:created, :preparing, :ready, :picked_up, :on_the_way, :delivered]

    Stream.iterate(0, &(&1 + 1))
    |> Stream.take(length(statuses))
    |> Stream.map(fn index ->
      # Delay de 2 segundos entre cada status (exceto o primeiro)
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
  Client Streaming: Restaurante envia items do pedido um por um
  Demonstra como processar um stream de mensagens do cliente
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

    # Retorna a resposta diretamente
    %PreparationSummary{
      order_id: result.order_id || "unknown",
      total_items: result.count,
      status: "ready"
    }
  end

  @doc """
  Bidirectional Streaming: Chat entre cliente e sistema
  Demonstra fluxo bidirecional unbounded com GenStage producer único.
  join_with junta stream do cliente com mensagens proativas do producer.
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
      # Mensagem do cliente - chama producer e retorna resposta
      %ChatMessage{} = msg ->
        response = GenStage.call(SystemMessageProducer, {:client_message, msg})

        %ChatMessage{
          order_id: msg.order_id,
          sender: "sistema",
          message: response,
          timestamp: System.system_time(:second)
        }

      # Mensagem proativa do producer (via join_with) - só converte
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
    # Aqui você salvaria no banco/ETS
    Logger.debug("Pedido #{order_id} salvo")
  end

  defp status_message(:created), do: "Pedido recebido"
  defp status_message(:preparing), do: "Restaurante está preparando"
  defp status_message(:ready), do: "Pedido pronto para retirada"
  defp status_message(:picked_up), do: "Entregador coletou o pedido"
  defp status_message(:on_the_way), do: "Entregador a caminho"
  defp status_message(:delivered), do: "Pedido entregue!"
end
