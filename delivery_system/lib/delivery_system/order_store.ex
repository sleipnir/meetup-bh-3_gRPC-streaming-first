defmodule DeliverySystem.OrderStore do
  @moduledoc """
  ETS-based storage for order state management.

  Provides persistence for orders across different RPC calls, enabling
  realistic order tracking and lifecycle management.

  ## Order Lifecycle States

  - `:created` - Order just created by customer
  - `:preparing` - Restaurant is preparing the order
  - `:ready` - Order is ready for pickup by driver
  - `:picked_up` - Driver has picked up the order
  - `:on_the_way` - Driver is delivering the order
  - `:delivered` - Order successfully delivered

  ## Usage

      # Save a new order
      OrderStore.save_order("ORD-123", %{
        customer_id: "C001",
        items: ["Pizza"],
        status: :created
      })
      
      # Update order status
      OrderStore.update_status("ORD-123", :ready)
      
      # Get orders by status
      ready_orders = OrderStore.get_orders_by_status(:ready)
  """

  use GenServer
  require Logger

  @table_name :order_store

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Saves a new order to the store.
  """
  def save_order(order_id, order_data) do
    order =
      Map.merge(order_data, %{
        order_id: order_id,
        created_at: System.system_time(:second),
        updated_at: System.system_time(:second)
      })

    :ets.insert(@table_name, {order_id, order})
    Logger.debug("📦 OrderStore: Saved order #{order_id}")
    :ok
  end

  @doc """
  Gets an order by ID.
  """
  def get_order(order_id) do
    case :ets.lookup(@table_name, order_id) do
      [{^order_id, order}] -> {:ok, order}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Updates the status of an order.
  """
  def update_status(order_id, new_status) do
    case get_order(order_id) do
      {:ok, order} ->
        updated_order =
          order
          |> Map.put(:status, new_status)
          |> Map.put(:updated_at, System.system_time(:second))

        :ets.insert(@table_name, {order_id, updated_order})
        Logger.debug("📦 OrderStore: Updated #{order_id} to status #{new_status}")
        {:ok, updated_order}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets all orders with a specific status.
  """
  def get_orders_by_status(status) do
    :ets.match(
      @table_name,
      {:"$1", %{status: status, order_id: :"$2", customer_id: :"$3", items: :"$4"}}
    )
    |> Enum.map(fn [_key, order_id, _customer_id, _items] ->
      {:ok, order} = get_order(order_id)
      order
    end)
  end

  @doc """
  Gets all orders (for debugging).
  """
  def all_orders do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {_id, order} -> order end)
  end

  @doc """
  Clears all orders (for testing).
  """
  def clear_all do
    :ets.delete_all_objects(@table_name)
    Logger.debug("📦 OrderStore: Cleared all orders")
    :ok
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    Logger.info("📦 OrderStore: ETS table initialized")
    {:ok, %{}}
  end
end
