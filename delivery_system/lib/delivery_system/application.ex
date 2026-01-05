defmodule DeliverySystem.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      # Inicia o supervisor de clientes gRPC
      GRPC.Client.Supervisor,
      # Producer único global para mensagens proativas do chat
      DeliverySystem.SystemMessageProducer,
      # Inicia o supervisor do gRPC Server
      {GRPC.Server.Supervisor, endpoint: DeliverySystem.Endpoint, port: 50051, start_server: true}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: DeliverySystem.Supervisor) do
      {:ok, pid} ->
        Logger.info("""

        ╔═══════════════════════════════════════════════════════════╗
        ║   🚀 Servidor gRPC do Sistema de Delivery iniciado!       ║
        ║                                                           ║
        ║   📍 Endereço: localhost:50051                            ║
        ║   🔧 Serviços: OrderService, DeliveryService              ║
        ║                                                           ║
        ║   Teste agora:                                            ║
        ║   {:ok, channel} = GRPC.Stub.connect("localhost:50051")   ║
        ╚═══════════════════════════════════════════════════════════╝
        """)

        {:ok, pid}

      error ->
        error
    end
  end
end
