defmodule DeliverySystem.Endpoint do
  @moduledoc """
  Endpoint principal que expõe os serviços de pedidos e entregas.
  """
  use GRPC.Endpoint

  intercept(GRPC.Server.Interceptors.Logger)
  run(DeliverySystem.Services.OrderServer)
  run(DeliverySystem.Services.DeliveryServer)
end
