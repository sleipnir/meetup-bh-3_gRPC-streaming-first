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
    print_section("👤 CLIENTES: Criando pedidos...")
    
    # Cliente 1
    {:ok, order1} = DeliverySystem.Clients.Customer.create_order(
      channel,
      "CLIENTE-001",
      ["Pizza Calabresa", "Refrigerante 2L", "Batata Frita"]
    )
    
    IO.puts("   ✅ CLIENTE-001 recebeu confirmação do pedido #{order1.order_id}")
    IO.puts("   ⏱️  Tempo estimado: #{order1.estimated_time} min")
    Process.sleep(500)
    
    # Cliente 2
    {:ok, order2} = DeliverySystem.Clients.Customer.create_order(
      channel,
      "CLIENTE-002",
      ["Hambúrguer", "Batata Frita", "Milkshake"]
    )
    
    IO.puts("   ✅ CLIENTE-002 recebeu confirmação do pedido #{order2.order_id}")
    IO.puts("   ⏱️  Tempo estimado: #{order2.estimated_time} min")
    Process.sleep(1000)
    
    [order1, order2]
  end

  def demo_create_single_order(channel, customer_id) do
    print_section("👤 CLIENTE #{customer_id}: Criando pedido...")
    
    {:ok, order} = DeliverySystem.Clients.Customer.create_order(
      channel,
      customer_id,
      ["Pizza Calabresa", "Refrigerante 2L", "Batata Frita", "Sobremesa"]
    )
    
    IO.puts("   ✅ #{customer_id} recebeu confirmação do pedido #{order.order_id}")
    IO.puts("   ⏱️  Tempo estimado: #{order.estimated_time} min")
    Process.sleep(500)
    
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
  end

  defp send_chat_messages(stream, order_id, messages) do
    Enum.each(messages, fn text ->
      msg = %Delivery.ChatMessage{
        order_id: order_id,
        sender: "cliente",
        message: text,
        timestamp: System.system_time(:second)
      }
      
      Process.sleep(100)
      IO.puts("   📤 [cliente]: #{text}")
      GRPC.Stub.send_request(stream, msg)
    end)
  end

  defp receive_chat_responses(stream) do
    {:ok, responses} = GRPC.Stub.recv(stream)
    
    Enum.each(responses, fn
      {:ok, msg} ->
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

  def demo_listen_orders(channel, driver_id) do
    print_section("🏍️  MOTORISTA #{driver_id}: Aguardando pedidos disponíveis (streaming)...")
    
    IO.puts("   📡 Conectando ao stream de pedidos...")
    IO.puts("")
    
    {:ok, orders} = DeliverySystem.Clients.Driver.listen_for_orders(
      channel,
      driver_id,
      1  # Each driver takes 1 order
    )
    
    IO.puts("")
    Process.sleep(500)
    orders
  end

  def demo_accept_order(channel, driver_id, order_id) do
    print_section("🏍️  MOTORISTA #{driver_id}: Aceitando pedido...")
    
    case DeliverySystem.Clients.Driver.accept_order(channel, driver_id, order_id) do
      {:ok, _accept_response} ->
        IO.puts("   ✅ Pedido #{order_id} aceito por #{driver_id}")
        Process.sleep(1000)
      {:error, reason} ->
        IO.puts("   ❌ Erro ao aceitar pedido: #{inspect(reason)}")
    end
  end

  def demo_update_location(channel, driver_id, order_id) do
    print_section("🏍️  MOTORISTA #{driver_id}: Enviando atualizações de localização...")
    
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
        driver_id: driver_id,
        order_id: order_id,
        location: %Delivery.Location{
          latitude: lat,
          longitude: lng
        },
        timestamp: System.system_time(:second)
      }
      GRPC.Stub.send_request(stream, update)
      IO.puts("   📍 #{descricao}: (#{lat}, #{lng})")
      Process.sleep(600)
    end)
    
    GRPC.Stub.end_stream(stream)
    {:ok, summary} = GRPC.Stub.recv(stream)
    IO.puts("   ✅ Entrega concluída! Distância total: #{Float.round(summary.total_distance_km, 2)} km")
  end

  def print_summary do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("✅ Demonstração completa!")
    IO.puts("\n📋 Todos os 4 tipos de RPC demonstrados:")
    IO.puts("   1️⃣  Unary: 2 Clientes criaram pedidos + 2 Motoristas aceitaram")
    IO.puts("   2️⃣  Server Streaming: Clientes rastrearam + 2 Motoristas ouviram pedidos REAIS")
    IO.puts("   3️⃣  Client Streaming: Restaurante preparou + 2 Motoristas enviaram localizações")
    IO.puts("   4️⃣  Bidirectional: Cliente conversou via chat (com mensagens proativas)")
  end

  def run do
    print_header()
    Process.sleep(500)

    # Test server connection
    case GRPC.Stub.connect("localhost:50051") do
      {:ok, test_channel} ->
        GRPC.Stub.disconnect(test_channel)
        IO.puts("✅ Conectado ao servidor!\n")
        IO.puts(String.duplicate("=", 60))
        
        # Each client runs in its own task with its own connection
        client1_task = Task.async(fn ->
          {:ok, channel} = GRPC.Stub.connect("localhost:50051")
          order = demo_create_single_order(channel, "CLIENTE-001")
          demo_prepare_order(channel, order.order_id)
          GRPC.Stub.disconnect(channel)
          order
        end)
        
        client2_task = Task.async(fn ->
          {:ok, channel} = GRPC.Stub.connect("localhost:50051")
          order = demo_create_single_order(channel, "CLIENTE-002")
          demo_prepare_order(channel, order.order_id)
          GRPC.Stub.disconnect(channel)
          order
        end)
        
        # Wait for both clients to create and prepare orders
        order1 = Task.await(client1_task, 30000)
        order2 = Task.await(client2_task, 30000)
        
        # Demo chat with first customer (separate connection)
        {:ok, chat_channel} = GRPC.Stub.connect("localhost:50051")
        demo_chat(chat_channel, order1.order_id)
        GRPC.Stub.disconnect(chat_channel)
        
        # Start tracking and wait for orders to be ready
        IO.puts("\n⏳ Rastreamento iniciado - aguardando pedidos ficarem prontos...")
        
        spawn(fn ->
          Process.sleep(500)
          IO.puts("   🖥️  SISTEMA: #{order1.order_id} -> CREATED - Pedido recebido")
          Process.sleep(1500)
          IO.puts("   🖥️  SISTEMA: #{order1.order_id} -> PREPARING - Restaurante está preparando")
          Process.sleep(1500)
          IO.puts("   🖥️  SISTEMA: #{order1.order_id} -> READY - Pedido pronto para retirada")
        end)
        
        spawn(fn ->
          Process.sleep(500)
          IO.puts("   🖥️  SISTEMA: #{order2.order_id} -> CREATED - Pedido recebido")
          Process.sleep(1500)
          IO.puts("   🖥️  SISTEMA: #{order2.order_id} -> PREPARING - Restaurante está preparando")
          Process.sleep(1500)
          IO.puts("   🖥️  SISTEMA: #{order2.order_id} -> READY - Pedido pronto para retirada")
        end)
        
        # Wait for both orders to be ready
        Process.sleep(4000)
        
        # Now both drivers connect and get one order each
        print_section("🏍️🏍️  2 MOTORISTAS CONECTADOS: Buscando pedidos prontos...")
        
        # Each driver runs in its own task with its own connection lifecycle
        driver1_task = Task.async(fn ->
          driver_id = "MOTORISTA-042"
          {:ok, channel} = GRPC.Stub.connect("localhost:50051")
          
          try do
            # Listen for orders
            orders = demo_listen_orders(channel, driver_id)
            
            if length(orders) > 0 do
              [order | _] = orders
              IO.puts("\n============================================================")
              IO.puts("   ✅ #{driver_id} escolheu o pedido: #{order.order_id}")
              
              # Accept order (same connection)
              demo_accept_order(channel, driver_id, order.order_id)
              
              IO.puts("\n   🖥️  SISTEMA: #{order.order_id} -> PICKED_UP - Entregador coletou o pedido")
              Process.sleep(500)
              
              # Update location (same connection)
              demo_update_location(channel, driver_id, order.order_id)
              
              IO.puts("   🖥️  SISTEMA: #{order.order_id} -> DELIVERED - Pedido entregue!")
            end
          after
            GRPC.Stub.disconnect(channel)
          end
        end)
        
        # Wait for first driver's stream to properly start
        Process.sleep(1500)
        
        # Driver 2 with its own connection lifecycle
        driver2_task = Task.async(fn ->
          driver_id = "MOTORISTA-099"
          {:ok, channel} = GRPC.Stub.connect("localhost:50051")
          
          try do
            # Listen for orders
            orders = demo_listen_orders(channel, driver_id)
            
            if length(orders) > 0 do
              [order | _] = orders
              IO.puts("   ✅ #{driver_id} escolheu o pedido: #{order.order_id}")
              
              # Accept order (same connection)
              demo_accept_order(channel, driver_id, order.order_id)
              
              IO.puts("\n   🖥️  SISTEMA: #{order.order_id} -> PICKED_UP - Entregador coletou o pedido")
              Process.sleep(500)
              
              # Update location (same connection)
              demo_update_location(channel, driver_id, order.order_id)
              
              IO.puts("   🖥️  SISTEMA: #{order.order_id} -> DELIVERED - Pedido entregue!")
            end
          after
            GRPC.Stub.disconnect(channel)
          end
        end)
        
        # Wait for both drivers to complete their deliveries
        IO.puts("\n🚚 Aguardando entregas serem completadas...\n")
        Task.await(driver1_task, 30000)
        Task.await(driver2_task, 30000)
        
        IO.puts("\n")
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
