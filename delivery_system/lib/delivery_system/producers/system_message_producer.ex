defmodule DeliverySystem.Producers.SystemMessageProducer do
  @moduledoc """
  Single global GenStage producer for proactive chat messages.
  Responds to GenStage.call calls and emits proactive messages via events.
  """
  use GenStage
  require Logger

  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:producer, %{}}
  end

  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end

  def handle_call({:client_message, msg}, _from, state) do
    # Respond to client message
    response = resposta_automatica(msg.message)

    # Schedule proactive messages
    Process.send_after(self(), {:proactive, msg.order_id}, 100)

    {:reply, response, [], state}
  end

  def handle_info({:proactive, order_id}, state) do
    # Send proactive messages
    messages = [
      {:system_message, order_id, "🔔 Atualização: Seu pedido está sendo preparado!"},
      {:system_message, order_id,
       "🔔 Atualização: Enquanto aguarda o que acha de dar uma nova olhada em nosso cardápio?"}
    ]

    {:noreply, messages, state}
  end

  defp resposta_automatica(message) do
    cond do
      String.contains?(String.downcase(message), "onde") ->
        "Seu pedido está a caminho!"

      String.contains?(String.downcase(message), "quanto tempo") ->
        "Estimativa de 15 minutos"

      String.contains?(String.downcase(message), "obrigado") ->
        "De nada! Bom apetite!"

      true ->
        "Recebemos sua mensagem!"
    end
  end
end
