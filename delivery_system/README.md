# Sistema de Delivery com gRPC Streaming

Sistema de exemplo demonstrando todos os tipos de streaming do gRPC em Elixir.

## 🎯 Objetivo

Demonstrar na prática os 4 tipos de RPC do gRPC:
- **Unary**: Cliente cria pedido
- **Server Streaming**: Cliente rastreia pedido em tempo real
- **Client Streaming**: Motorista envia atualizações de localização
- **Bidirectional Streaming**: Chat entre cliente e entregador

## 📦 Instalação

```bash
# Instalar dependências
mix deps.get

# Compilar
mix compile
```

## 🚀 Rodando o Servidor

```bash
# Iniciar o servidor gRPC na porta 50051
iex -S mix
```

## 💻 Exemplos de Uso

### Terminal 1: Iniciar o Servidor
```elixir
iex -S mix
# Servidor rodando em localhost:50051
```

### Terminal 2: Cliente (Pedidos)

```elixir
# Iniciar IEx
iex -S mix

# Conectar ao servidor
{:ok, channel} = GRPC.Stub.connect("localhost:50051")

# 1️⃣ UNARY: Criar um pedido
{:ok, order} = DeliverySystem.Clients.Customer.create_order(
  channel,
  "CUST-001",
  ["Pizza", "Refrigerante", "Sobremesa"]
)

# 2️⃣ SERVER STREAMING: Rastrear pedido em tempo real
DeliverySystem.Clients.Customer.track_order(channel, order.order_id)
# Você verá as atualizações: created -> preparing -> ready -> picked_up -> delivered

# 3️⃣ BIDIRECTIONAL STREAMING: Chat com entregador
DeliverySystem.Clients.Customer.start_chat(channel, order.order_id)
```

### Terminal 3: Motorista (Entregas)

```elixir
# Iniciar IEx
iex -S mix

# Conectar ao servidor
{:ok, channel} = GRPC.Stub.connect("localhost:50051")

# 1️⃣ SERVER STREAMING: Receber pedidos disponíveis (recebe 3 pedidos)
DeliverySystem.Clients.Driver.listen_for_orders(channel, "DRIVER-001", 3)

# 2️⃣ UNARY: Aceitar um pedido
DeliverySystem.Clients.Driver.accept_order(channel, "DRIVER-001", "ORD-123")

# 3️⃣ CLIENT STREAMING: Enviar atualizações de localização
DeliverySystem.Clients.Driver.send_location_updates(
  channel,
  "DRIVER-001",
  "ORD-123",
  5  # número de atualizações
)
```

## 🔄 Tipos de Streaming Demonstrados

### 1. Unary RPC
**Arquivo**: `lib/delivery_system/services/order_server.ex`
**Função**: `create_order/2`
```elixir
# Cliente envia 1 mensagem, servidor responde 1 mensagem
def create_order(request, materializer) do
  GRPC.Stream.unary(request, materializer: materializer)
  |> GRPC.Stream.map(&process_order/1)
  |> GRPC.Stream.run()
end
```

### 2. Server Streaming
**Arquivo**: `lib/delivery_system/services/order_server.ex`
**Função**: `track_order/2`
```elixir
# Cliente envia 1 mensagem, servidor envia STREAM de respostas
def track_order(request, materializer) do
  Stream.unfold(:created, &status_updater/1)
  |> GRPC.Stream.from()
  |> GRPC.Stream.run_with(materializer)
end
```

### 3. Client Streaming
**Arquivo**: `lib/delivery_system/services/delivery_server.ex`
**Função**: `update_location/2`
```elixir
# Cliente envia STREAM de mensagens, servidor responde 1 mensagem
def update_location(location_stream, materializer) do
  GRPC.Stream.from(location_stream)
  |> GRPC.Stream.reduce(fn -> initial_state end, &accumulator/2)
  |> GRPC.Stream.run_with(materializer)
end
```

### 4. Bidirectional Streaming
**Arquivo**: `lib/delivery_system/services/order_server.ex`
**Função**: `order_chat/2`
```elixir
# Cliente e servidor trocam STREAMS independentes
def order_chat(messages_stream, materializer) do
  GRPC.Stream.from(messages_stream, join_with: system_producer)
  |> GRPC.Stream.map(&process_message/1)
  |> GRPC.Stream.run_with(materializer)
end
```

## 📁 Estrutura do Projeto

```
delivery_system/
├── lib/
│   └── delivery_system/
│       ├── protos.ex                    # Definições Protobuf
│       ├── endpoint.ex                  # Endpoint gRPC
│       ├── application.ex               # Application supervisor
│       ├── services/
│       │   ├── order_server.ex         # Servidor de pedidos
│       │   └── delivery_server.ex      # Servidor de entregas
│       └── clients/
│           ├── customer.ex             # Cliente simulando pedidos
│           └── driver.ex               # Cliente simulando motorista
├── priv/
│   └── protos/
│       └── delivery.proto              # Definições Protocol Buffers
└── mix.exs
```

## 🎓 Para a Apresentação

Este projeto demonstra:

1. ✅ **API Streaming-first do elixir-grpc**
2. ✅ **Uso de GRPC.Stream com Flow e GenStage**
3. ✅ **Backpressure automático com max_demand**
4. ✅ **Composição funcional de streams**
5. ✅ **Integração com produtores externos (join_with)**
6. ✅ **Tratamento de erros com map_error**
7. ✅ **Side-effects com effect**

## 🔧 Funções Principais da API

- `GRPC.Stream.from/2` - Cria stream com backpressure
- `GRPC.Stream.unary/2` - Stream de 1 elemento
- `GRPC.Stream.map/2` - Transforma elementos
- `GRPC.Stream.filter/2` - Filtra elementos
- `GRPC.Stream.reduce/3` - Agrega elementos
- `GRPC.Stream.effect/2` - Side-effects
- `GRPC.Stream.run/1` - Executa unary
- `GRPC.Stream.run_with/3` - Executa streaming

## 📚 Referências

- [elixir-grpc GitHub](https://github.com/elixir-grpc/grpc)
- [Documentação GRPC.Stream](https://hexdocs.pm/grpc/GRPC.Stream.html)
- [gRPC.io](https://grpc.io)

