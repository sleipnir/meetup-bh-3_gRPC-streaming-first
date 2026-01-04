# Gerado automaticamente a partir de delivery.proto
# Para regerar: mix protobuf.generate

defmodule Delivery.Location do
  use Protobuf, syntax: :proto3
  field(:latitude, 1, type: :double)
  field(:longitude, 2, type: :double)
end

defmodule Delivery.OrderRequest do
  use Protobuf, syntax: :proto3
  field(:customer_id, 1, type: :string)
  field(:restaurant_id, 2, type: :string)
  field(:items, 3, repeated: true, type: :string)
  field(:delivery_address, 4, type: :string)
end

defmodule Delivery.OrderResponse do
  use Protobuf, syntax: :proto3
  field(:order_id, 1, type: :string)
  field(:status, 2, type: :string)
  field(:estimated_time, 3, type: :double)
end

defmodule Delivery.TrackRequest do
  use Protobuf, syntax: :proto3
  field(:order_id, 1, type: :string)
end

defmodule Delivery.OrderStatus do
  use Protobuf, syntax: :proto3
  field(:order_id, 1, type: :string)
  field(:status, 2, type: :string)
  field(:message, 3, type: :string)
  field(:timestamp, 4, type: :int64)
  field(:current_location, 5, type: Delivery.Location, optional: true)
end

defmodule Delivery.OrderItem do
  use Protobuf, syntax: :proto3
  field(:order_id, 1, type: :string)
  field(:item_name, 2, type: :string)
  field(:quantity, 3, type: :int32)
  field(:notes, 4, type: :string)
end

defmodule Delivery.PreparationSummary do
  use Protobuf, syntax: :proto3
  field(:order_id, 1, type: :string)
  field(:total_items, 2, type: :int32)
  field(:status, 3, type: :string)
end

defmodule Delivery.DriverRequest do
  use Protobuf, syntax: :proto3
  field(:driver_id, 1, type: :string)
  field(:current_location, 2, type: Delivery.Location)
end

defmodule Delivery.DeliveryOrder do
  use Protobuf, syntax: :proto3
  field(:order_id, 1, type: :string)
  field(:restaurant_name, 2, type: :string)
  field(:restaurant_address, 3, type: :string)
  field(:delivery_address, 4, type: :string)
  field(:distance_km, 5, type: :double)
  field(:estimated_payment, 6, type: :double)
end

defmodule Delivery.AcceptRequest do
  use Protobuf, syntax: :proto3
  field(:driver_id, 1, type: :string)
  field(:order_id, 2, type: :string)
end

defmodule Delivery.AcceptResponse do
  use Protobuf, syntax: :proto3
  field(:success, 1, type: :bool)
  field(:message, 2, type: :string)
  field(:order, 3, type: Delivery.DeliveryOrder)
end

defmodule Delivery.LocationUpdate do
  use Protobuf, syntax: :proto3
  field(:driver_id, 1, type: :string)
  field(:order_id, 2, type: :string)
  field(:location, 3, type: Delivery.Location)
  field(:timestamp, 4, type: :int64)
end

defmodule Delivery.LocationSummary do
  use Protobuf, syntax: :proto3
  field(:driver_id, 1, type: :string)
  field(:updates_received, 2, type: :int32)
  field(:total_distance_km, 3, type: :double)
end

defmodule Delivery.ChatMessage do
  use Protobuf, syntax: :proto3
  field(:order_id, 1, type: :string)
  field(:sender, 2, type: :string)
  field(:message, 3, type: :string)
  field(:timestamp, 4, type: :int64)
end

# Definições dos serviços
defmodule Delivery.OrderService.Service do
  use GRPC.Service, name: "delivery.OrderService"

  rpc(:CreateOrder, Delivery.OrderRequest, Delivery.OrderResponse)
  rpc(:TrackOrder, Delivery.TrackRequest, stream(Delivery.OrderStatus))
  rpc(:PrepareOrder, stream(Delivery.OrderItem), Delivery.PreparationSummary)
  rpc(:OrderChat, stream(Delivery.ChatMessage), stream(Delivery.ChatMessage))
end

defmodule Delivery.OrderService.Stub do
  use GRPC.Stub, service: Delivery.OrderService.Service
end

defmodule Delivery.DeliveryService.Service do
  use GRPC.Service, name: "delivery.DeliveryService"

  rpc(:StreamAvailableOrders, Delivery.DriverRequest, stream(Delivery.DeliveryOrder))
  rpc(:AcceptOrder, Delivery.AcceptRequest, Delivery.AcceptResponse)
  rpc(:UpdateLocation, stream(Delivery.LocationUpdate), Delivery.LocationSummary)
end

defmodule Delivery.DeliveryService.Stub do
  use GRPC.Stub, service: Delivery.DeliveryService.Service
end
