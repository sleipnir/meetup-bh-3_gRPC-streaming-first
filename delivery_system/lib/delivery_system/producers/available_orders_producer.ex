defmodule DeliverySystem.Producers.AvailableOrdersProducer do
  @moduledoc """
  GenStage producer that emits available orders periodically.
  Demonstrates server-side streaming with proactive message generation.
  """
  use GenStage
  require Logger

  alias Delivery.DeliveryOrder

  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:producer, %{}}
  end

  def handle_demand(demand, state) when demand > 0 do
    # Generate orders based on demand
    orders =
      Enum.map(1..demand, fn _ ->
        # Simulate delay between orders
        Process.sleep(:rand.uniform(1500) + 500)

        order = %DeliveryOrder{
          order_id: "ORD-#{:rand.uniform(999_999)}",
          restaurant_name: random_restaurant(),
          restaurant_address: "Rua A, 123",
          delivery_address: "Rua B, 456",
          distance_km: :rand.uniform(10) * 1.0,
          estimated_payment: 10.0 + :rand.uniform(20) * 1.0
        }

        {:available_order, order}
      end)

    {:noreply, orders, state}
  end

  defp random_restaurant do
    restaurants = [
      "Pizzaria Bella",
      "Burguer King",
      "Sushi House",
      "Taco Bell",
      "McDonald's"
    ]

    Enum.random(restaurants)
  end
end
