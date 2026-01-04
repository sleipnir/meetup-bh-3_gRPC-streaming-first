# 🚀 Guia Rápido - Sistema de Delivery

## ⚡ Início Rápido - 3 Passos

### 1️⃣ Iniciar IEx
```bash
cd delivery_system
iex -S mix
```

### 2️⃣ Garantir que o servidor está rodando
```elixir
# No prompt do iex, rode:
Application.ensure_all_started(:delivery_system)
```

Aguarde alguns segundos. Você deve ver:
```
🚀 Servidor gRPC do Sistema de Delivery iniciado!
📍 Endereço: localhost:50051
```

### 3️⃣ Testar
```elixir
# No mesmo terminal iex:
{:ok, channel} = GRPC.Stub.connect("localhost:50051")

# Criar pedido
{:ok, order} = DeliverySystem.Clients.Customer.create_order(
  channel,
  "CUST-001",
  ["Pizza Margherita"]
)

IO.inspect(order)
```

## 🧪 Teste Automatizado

```bash
cd delivery_system
iex -S mix
```

```elixir
# Cole e execute:
import_file("scripts/test_connection.exs")
```

## 📖 Exemplos Práticos

### 1. Criar e Rastrear Pedido (Unary + Server Streaming)

```elixir
# Conectar
{:ok, channel} = GRPC.Stub.connect("localhost:50051")

# Criar pedido (UNARY)
{:ok, order} = DeliverySystem.Clients.Customer.create_order(
  channel,
  "CUST-001",
  ["Pizza Margherita", "Coca-Cola", "Brownie"]
)

# Rastrear pedido (SERVER STREAMING)
DeliverySystem.Clients.Customer.track_order(channel, order.order_id)
```

### 2. Motorista Recebendo Pedidos (Server Streaming)

```elixir
# Conectar
{:ok, channel} = GRPC.Stub.connect("localhost:50051")

# Receber stream de pedidos disponíveis
DeliverySystem.Clients.Driver.listen_for_orders(channel, "DRIVER-001", 3)
```

### 3. Motorista Enviando Localização (Client Streaming)

```elixir
# Conectar
{:ok, channel} = GRPC.Stub.connect("localhost:50051")

# Aceitar pedido (UNARY)
DeliverySystem.Clients.Driver.accept_order(channel, "DRIVER-001", "ORD-1")

# Enviar stream de localizações (CLIENT STREAMING)
DeliverySystem.Clients.Driver.send_location_updates(
  channel,
  "DRIVER-001",
  "ORD-1",
  10  # 10 atualizações
)
```

### 4. Chat Bidirecional (Bidirectional Streaming)

```elixir
# Conectar
{:ok, channel} = GRPC.Stub.connect("localhost:50051")

# Iniciar chat (BIDIRECTIONAL)
DeliverySystem.Clients.Customer.start_chat(channel, "ORD-123")
```

## 📝 Para a Apresentação

### Demonstração ao Vivo

**Terminal 1 - Servidor:**
```bash
iex -S mix
# Mostra logs dos eventos
```

**Terminal 2 - Cliente:**
```elixir
{:ok, channel} = GRPC.Stub.connect("localhost:50051")
{:ok, order} = DeliverySystem.Clients.Customer.create_order(channel, "CUST-001", ["Pizza"])
DeliverySystem.Clients.Customer.track_order(channel, order.order_id)
```

**Terminal 3 - Motorista:**
```elixir
{:ok, channel} = GRPC.Stub.connect("localhost:50051")
DeliverySystem.Clients.Driver.listen_for_orders(channel, "DRIVER-001", 2)
```

### Pontos para Destacar

1. **Unary**: Simples e direto - criar pedido
2. **Server Streaming**: Atualizações em tempo real - rastrear pedido
3. **Client Streaming**: Cliente envia múltiplas mensagens - localização
4. **Bidirectional**: Ambos trocam mensagens - chat

### Código para Mostrar

**API Streaming-first:**
```elixir
# Tudo é um stream!
GRPC.Stream.from(input)
|> GRPC.Stream.map(&process/1)
|> GRPC.Stream.filter(&valid?/1)
|> GRPC.Stream.effect(&log/1)
|> GRPC.Stream.run_with(materializer)
```

**Backpressure:**
```elixir
GRPC.Stream.from(input, max_demand: 10)
```

**Join with external producer:**
```elixir
GRPC.Stream.from(input, join_with: external_pid)
```

## 🎯 Arquivos Importantes

- `lib/delivery_system/protos.ex` - Definições Protobuf
- `lib/delivery_system/services/order_server.ex` - Exemplos de todos os tipos
- `lib/delivery_system/services/delivery_server.ex` - Mais exemplos
- `priv/protos/delivery.proto` - Definição dos serviços

## 📖 Documentação

- [README.md](README.md) - Documentação completa
- [GRPC.Stream](https://hexdocs.pm/grpc/GRPC.Stream.html) - API Reference
