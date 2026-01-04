defmodule DeliverySystem.MixProject do
  use Mix.Project

  def project do
    [
      app: :delivery_system,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {DeliverySystem.Application, []}
    ]
  end

  defp deps do
    [
      {:grpc, "~> 0.11"},
      {:protobuf, "~> 0.14"},
      {:grpc_reflection, "~> 0.2"},
      {:protobuf_generate, "~> 0.1", only: :dev}
    ]
  end
end
