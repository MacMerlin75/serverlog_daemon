defmodule ServerlogDaemon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: ServerlogDaemon.Worker.start_link(arg)
      # {Phoenix.PubSub, name: PubSub}
      # {ServerlogDaemon.StateWorker, %{}}
      {DynamicSupervisor, name: ServerlogDaemon.DynamicSupervisor, strategy: :one_for_one}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ServerlogDaemon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
