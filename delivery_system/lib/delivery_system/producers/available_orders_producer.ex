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
    # Store driver subscriptions: which drivers have been assigned orders
    # {driver_pid => %{driver_id: id, order_assigned: order_id or nil}}
    {:producer, %{subscribers: %{}}}
  end

  @doc """
  Request an available order for a specific driver
  """
  def request_order(driver_id) do
    GenStage.call(__MODULE__, {:request_order, driver_id})
  end

  def handle_call({:request_order, driver_id}, _from, state) do
    # Get ready orders from OrderStore that haven't been assigned yet
    ready_orders = DeliverySystem.OrderStore.get_orders_by_status(:ready)

    case ready_orders do
      [order | _] ->
        # Mark order as assigned
        DeliverySystem.OrderStore.update_status(order.order_id, :assigned)

        delivery_order = %DeliveryOrder{
          order_id: order.order_id,
          restaurant_name: random_restaurant(),
          restaurant_address: "Rua A, 123",
          delivery_address: "Rua B, 456",
          distance_km: :rand.uniform(10) * 1.0,
          estimated_payment: 10.0 + :rand.uniform(20) * 1.0
        }

        Logger.info("✅ Assigned order #{order.order_id} to driver #{driver_id}")
        {:reply, {:ok, delivery_order}, [], state}

      [] ->
        {:reply, {:error, :no_orders_available}, [], state}
    end
  end

  # Since we're using GenStage.call instead of join_with, we don't need handle_demand
  def handle_demand(_demand, state) do
    {:noreply, [], state}
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
