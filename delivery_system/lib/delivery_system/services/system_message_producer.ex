defmodule SystemMessageProducer do
  @moduledoc """
  GenStage producer único global para mensagens proativas do chat.
  Responde a chamadas GenStage.call e emite mensagens proativas via eventos.
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
    # Responde à mensagem do cliente
    response = resposta_automatica(msg.message)
    
    # Agenda mensagens proativas
    Process.send_after(self(), {:proactive, msg.order_id}, 800)
    
    {:reply, response, [], state}
  end

  def handle_info({:proactive, order_id}, state) do
    # Envia mensagens proativas
    messages = [
      {:system_message, order_id, "🔔 Atualização: Seu pedido está sendo preparado!"},
      {:system_message, order_id, "✅ Pedido pronto para envio!"}
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
