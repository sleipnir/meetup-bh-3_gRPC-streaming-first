#!/usr/bin/env elixir

# Script de demonstração do Sistema de Delivery
# 
# IMPORTANTE: O servidor já deve estar rodando!
# Em outro terminal: iex -S mix
#
# Execute este script com:
#   mix run scripts/demo.exs

IO.puts("""
╔═══════════════════════════════════════════════════════════╗
║   🍕 Sistema de Delivery - Demonstração gRPC Streaming    ║
╚═══════════════════════════════════════════════════════════╝

Este script demonstra os 4 tipos de RPC do gRPC com diferentes atores:

👤 CLIENTE  - Cria e acompanha pedidos
🏍️  MOTORISTA - Aceita pedidos e atualiza localização
🍽️  RESTAURANTE - Prepara pedidos

Conectando em localhost:50051...
""")

# Aguarda um pouco para garantir que tudo está pronto
Process.sleep(500)

# Testar conexão
case GRPC.Stub.connect("localhost:50051") do
  {:ok, channel} ->
    IO.puts("✅ Conectado ao servidor!\n")
    IO.puts(String.duplicate("=", 60))
    
    # Demonstração 1: Unary - Cliente cria pedido
    IO.puts("\n👤 CLIENTE: Criando pedido...")
    IO.puts(String.duplicate("-", 60))
    {:ok, order} = DeliverySystem.Clients.Customer.create_order(
      channel,
      "CLIENTE-001",
      ["Pizza Calabresa", "Refrigerante 2L", "Batata Frita"]
    )
    IO.puts("   ✅ Cliente recebeu confirmação do pedido #{order.order_id}")
    IO.puts("   ⏱️  Tempo estimado: #{order.estimated_time} min")
    
    Process.sleep(1000)
    
    # Demonstração 2: Bidirectional Streaming - Chat entre cliente e sistema
    IO.puts("\n💬 CHAT: Diálogo entre cliente e sistema...")
    IO.puts(String.duplicate("-", 60))
    
    chat_stream = Delivery.OrderService.Stub.order_chat(channel)
    
    # Mensagens para criar um diálogo natural
    conversations = [
      "Olá, onde está meu pedido?",
      "Quanto tempo ainda falta?",
      "Ok, obrigado!"
    ]
    
    # Enviar todas as mensagens com pequenos delays para simular digitação
    Enum.each(conversations, fn text ->
      msg = %Delivery.ChatMessage{
        order_id: order.order_id,
        sender: "cliente",
        message: text,
        timestamp: System.system_time(:second)
      }
      
      # Delay antes de mostrar a mensagem (simula tempo de digitação)
      Process.sleep(300)
      IO.puts("   📤 [cliente]: #{text}")
      GRPC.Stub.send_request(chat_stream, msg)
    end)
    
    # Finalizar envio
    GRPC.Stub.end_stream(chat_stream)
    
    # Receber e mostrar respostas conforme chegam (incluindo mensagens proativas)
    {:ok, responses} = GRPC.Stub.recv(chat_stream)
    
    responses
    |> Enum.each(fn
      {:ok, msg} ->
        # Pequeno delay antes de mostrar resposta (simula tempo de processamento)
        Process.sleep(150)
        if String.contains?(msg.message, ["🔔", "✅"]) do
          IO.puts("   📩 [#{msg.sender}] 🎯: #{msg.message}")
        else
          IO.puts("   📩 [#{msg.sender}]: #{msg.message}")
        end
      _ -> 
        :ok
    end)
    
    IO.puts("   ✅ Chat encerrado!")
    
    Process.sleep(1000)
    
    # Demonstração 3: Client Streaming - Restaurante prepara itens do pedido
    IO.puts("\n🍽️  RESTAURANTE: Preparando items do pedido...")
    IO.puts(String.duplicate("-", 60))
    
    prep_stream = Delivery.OrderService.Stub.prepare_order(channel)
    
    items = ["Pizza Calabresa", "Refrigerante 2L", "Batata Frita", "Sobremesa"]
    Enum.each(items, fn item_name ->
      item = %Delivery.OrderItem{
        order_id: order.order_id,
        item_name: item_name,
        quantity: 1
      }
      GRPC.Stub.send_request(prep_stream, item)
      IO.puts("   🔪 Preparando: #{item_name}")
      Process.sleep(500)
    end)
    
    GRPC.Stub.end_stream(prep_stream)
    {:ok, prep_summary} = GRPC.Stub.recv(prep_stream)
    IO.puts("   ✅ Preparação concluída! Total de #{prep_summary.total_items} items - Status: #{prep_summary.status}")
    
    Process.sleep(1500)
    
    # Demonstração 4: Server Streaming - Cliente rastreia pedido
    IO.puts("\n👤 CLIENTE: Acompanhando status do pedido em tempo real...")
    IO.puts(String.duplicate("-", 60))
    
    # Criar uma task para rastrear o pedido sem bloquear
    track_task = Task.async(fn ->
      DeliverySystem.Clients.Customer.track_order(channel, order.order_id)
    end)
    
    # Enquanto o cliente rastreia, simular outras operações
    Process.sleep(3000)
    
    # Demonstração 5: Unary - Motorista aceita o pedido
    IO.puts("\n🏍️  MOTORISTA: Aceitando o pedido...")
    IO.puts(String.duplicate("-", 60))
    accept_request = %Delivery.AcceptRequest{
      driver_id: "MOTORISTA-042",
      order_id: order.order_id
    }
    {:ok, accept_response} = Delivery.DeliveryService.Stub.accept_order(channel, accept_request)
    if accept_response.success do
      IO.puts("   ✅ Motorista #{accept_request.driver_id} aceitou o pedido!")
    end
    
    Process.sleep(2000)
    
    # Demonstração 6: Client Streaming - Motorista atualiza localização
    IO.puts("\n🏍️  MOTORISTA: Enviando atualizações de localização durante a entrega...")
    IO.puts(String.duplicate("-", 60))
    
    stream = Delivery.DeliveryService.Stub.update_location(channel)
    
    # Simular 5 atualizações de localização
    locations = [
      {-23.5505, -46.6333, "Saindo do restaurante"},
      {-23.5515, -46.6343, "Avenida Paulista"},
      {-23.5525, -46.6353, "Próximo ao destino"},
      {-23.5535, -46.6363, "Entrando na rua"},
      {-23.5545, -46.6373, "Chegou ao destino"}
    ]
    
    Enum.each(locations, fn {lat, lng, descricao} ->
      update = %Delivery.LocationUpdate{
        driver_id: "MOTORISTA-042",
        order_id: order.order_id,
        location: %Delivery.Location{
          latitude: lat,
          longitude: lng
        },
        timestamp: System.system_time(:second)
      }
      GRPC.Stub.send_request(stream, update)
      IO.puts("   📍 #{descricao}: (#{lat}, #{lng})")
      Process.sleep(800)
    end)
    
    # Finaliza o stream de localização
    GRPC.Stub.end_stream(stream)
    {:ok, summary} = GRPC.Stub.recv(stream)
    IO.puts("   ✅ Entrega concluída! Distância total: #{Float.round(summary.total_distance_km, 2)} km")
    
    # Aguarda a task de rastreamento completar
    Task.await(track_task, 20000)
    
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("✅ Demonstração completa!")
    IO.puts("\n📋 Todos os 4 tipos de RPC demonstrados:")
    IO.puts("   1️⃣  Unary: Cliente criou pedido + Motorista aceitou")
    IO.puts("   2️⃣  Bidirectional: Cliente perguntou sobre o pedido via chat")
    IO.puts("   3️⃣  Client Streaming: Restaurante preparou 4 items + Motorista enviou 5 localizações (0.63km)")
    IO.puts("   4️⃣  Server Streaming: Cliente rastreou 6 atualizações de status em tempo real")
    System.halt(0)
    
  {:error, reason} ->
    IO.puts("❌ Erro ao conectar: #{inspect(reason)}")
    IO.puts("\n⚠️  O servidor NÃO está rodando!")
    IO.puts("\nPara iniciar o servidor, abra outro terminal e execute:")
    IO.puts("  cd delivery_system")
    IO.puts("  iex -S mix")
    IO.puts("\nDepois execute este script novamente:")
    IO.puts("  mix run scripts/demo.exs\n")
    System.halt(1)
end
