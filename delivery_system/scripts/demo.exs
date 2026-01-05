#!/usr/bin/env elixir

# gRPC Delivery System Demo
# Demonstrates all 4 RPC types with streaming examples

defmodule Demo do
  def print_header do
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
  end

  def print_section(title) do
    IO.puts("\n#{title}")
    IO.puts(String.duplicate("-", 60))
  end

  def demo_create_order(channel) do
    print_section("👤 CLIENTE: Criando pedido...")
    
    {:ok, order} = DeliverySystem.Clients.Customer.create_order(
      channel,
      "CLIENTE-001",
      ["Pizza Calabresa", "Refrigerante 2L", "Batata Frita"]
    )
    
    IO.puts("   ✅ Cliente recebeu confirmação do pedido #{order.order_id}")
    IO.puts("   ⏱️  Tempo estimado: #{order.estimated_time} min")
    Process.sleep(1000)
    
    order
  end

  def demo_chat(channel, order_id) do
    print_section("💬 CHAT: Diálogo entre cliente e sistema...")
    
    chat_stream = Delivery.OrderService.Stub.order_chat(channel)
    
    conversations = [
      "Olá, onde está meu pedido?",
      "Quanto tempo ainda falta?",
      "Ok, obrigado!"
    ]
    
    send_chat_messages(chat_stream, order_id, conversations)
    GRPC.Stub.end_stream(chat_stream)
    
    receive_chat_responses(chat_stream)
    
    IO.puts("   ✅ Chat encerrado!")
    Process.sleep(1000)
  end

  defp send_chat_messages(stream, order_id, messages) do
    Enum.each(messages, fn text ->
      msg = %Delivery.ChatMessage{
        order_id: order_id,
        sender: "cliente",
        message: text,
        timestamp: System.system_time(:second)
      }
      
      Process.sleep(300)
      IO.puts("   📤 [cliente]: #{text}")
      GRPC.Stub.send_request(stream, msg)
    end)
  end

  defp receive_chat_responses(stream) do
    {:ok, responses} = GRPC.Stub.recv(stream)
    
    Enum.each(responses, fn
      {:ok, msg} ->
        Process.sleep(150)
        icon = if String.contains?(msg.message, ["🔔", "✅"]), do: " 🎯", else: ""
        IO.puts("   📩 [#{msg.sender}]#{icon}: #{msg.message}")
      _ -> 
        :ok
    end)
  end

  def demo_prepare_order(channel, order_id) do
    print_section("🍽️  RESTAURANTE: Preparando items do pedido...")
    
    prep_stream = Delivery.OrderService.Stub.prepare_order(channel)
    
    items = ["Pizza Calabresa", "Refrigerante 2L", "Batata Frita", "Sobremesa"]
    
    Enum.each(items, fn item_name ->
      item = %Delivery.OrderItem{
        order_id: order_id,
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
  end

  def demo_track_order_async(channel, order_id) do
    print_section("👤 CLIENTE: Acompanhando status do pedido em tempo real...")
    
    Task.async(fn ->
      DeliverySystem.Clients.Customer.track_order(channel, order_id)
    end)
  end

  def demo_listen_orders(channel) do
    print_section("🏍️  MOTORISTA: Aguardando pedidos disponíveis (streaming)...")
    
    {:ok, _available_orders} = DeliverySystem.Clients.Driver.listen_for_orders(
      channel,
      "MOTORISTA-042",
      2
    )
    Process.sleep(1000)
  end

  def demo_accept_order(channel, order_id) do
    print_section("🏍️  MOTORISTA: Aceitando pedido específico...")
    
    {:ok, _accept_response} = DeliverySystem.Clients.Driver.accept_order(
      channel,
      "MOTORISTA-042",
      order_id
    )
    Process.sleep(2000)
  end

  def demo_update_location(channel, order_id) do
    print_section("🏍️  MOTORISTA: Enviando atualizações de localização durante a entrega...")
    
    stream = Delivery.DeliveryService.Stub.update_location(channel)
    
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
        order_id: order_id,
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
    
    GRPC.Stub.end_stream(stream)
    {:ok, summary} = GRPC.Stub.recv(stream)
    IO.puts("   ✅ Entrega concluída! Distância total: #{Float.round(summary.total_distance_km, 2)} km")
  end

  def print_summary do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("✅ Demonstração completa!")
    IO.puts("\n📋 Todos os 4 tipos de RPC demonstrados:")
    IO.puts("   1️⃣  Unary: Cliente criou pedido + Motorista aceitou pedido")
    IO.puts("   2️⃣  Server Streaming: Cliente rastreou status + Motorista ouviu pedidos disponíveis")
    IO.puts("   3️⃣  Client Streaming: Restaurante preparou items + Motorista enviou localizações")
    IO.puts("   4️⃣  Bidirectional: Cliente conversou via chat (com mensagens proativas do servidor)")
  end

  def run do
    print_header()
    Process.sleep(500)

    case GRPC.Stub.connect("localhost:50051") do
      {:ok, channel} ->
        IO.puts("✅ Conectado ao servidor!\n")
        IO.puts(String.duplicate("=", 60))
        
        # Execute all demonstrations
        order = demo_create_order(channel)
        demo_chat(channel, order.order_id)
        demo_prepare_order(channel, order.order_id)
        
        track_task = demo_track_order_async(channel, order.order_id)
        Process.sleep(2000)
        
        demo_listen_orders(channel)
        demo_accept_order(channel, order.order_id)
        demo_update_location(channel, order.order_id)
        
        Task.await(track_task, 20000)
        
        print_summary()
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
  end
end

Demo.run()
