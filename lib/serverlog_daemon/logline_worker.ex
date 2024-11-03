defmodule ServerlogDaemon.LoglineWorker do
  @moduledoc false
  use GenServer, restart: :transient, shutdown: 10_000
  alias Phoenix.PubSub
  alias ServerlogDaemon.LoglineMapper
  require Logger

  @pubsub_server Application.compile_env!(:serverlog_daemon, :pubsub_server)


  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)

    {:ok, args}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: args.name)
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning("terminate/2 callbac @ logline_worker")
    # IO.inspect(Map.take(state, [queue]))
    Logger.warning("Going Down #{reason}: #{inspect(state)}")
    Logger.error("what is this....")
    :normal
  end

  @impl true
  def handle_info(:read_logline, %{queue: []} = state) do
    Logger.debug("#{state.short_name}: no new logline in queue!")

    {:noreply, state}
  end

  @impl true
  def handle_info(:read_logline, %{server_id: server_id, queue: [logline | rest]} = state) do
    [ts, message] = String.split(logline, ":", parts: 2)

    PubSub.broadcast(@pubsub_server, "gameserver_id_#{server_id}", {:data, server_id, :logline,  %{ts: ts, message: message}})

    ref = Process.send_after(self(), :read_logline, 50)
    state
    |> Map.put(:timer_ref, ref)
    |> Map.put(:queue, rest)
    |> LoglineMapper.map(logline)
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_cast({:push, loglist}, %{timer_ref: timer_ref, queue: queue} = state) do
    Logger.info("pushing #{length(loglist)} log_lines to #{state.name}-queue")
    if timer_ref, do: Process.cancel_timer(timer_ref)


    Map.put(state, :queue, queue ++ loglist)
    |> then(fn state ->
      ref = Process.send_after(self(), :read_logline, 1)
      Map.put(state, :timer_ref, ref)
      |> then(&{:noreply, &1})
    end)
  end
end
