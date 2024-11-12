defmodule ServerlogDaemon.LoglineWorker do
  @moduledoc false
  use GenServer, restart: :transient, shutdown: 10_000
  alias Phoenix.PubSub
  alias ServerlogDaemon.LoglineMapper
  require Logger

  @pubsub_server Application.compile_env!(:serverlog_daemon, :pubsub_server)

  @impl true
  def init(args) do
    # Process.flag(:trap_exit, true)
    Process.send_after(self(), :send_worker_state, 5_000)
    {:ok, args}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: args.name)
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning("terminate/2 callbac @ logline_worker")
    Logger.warning("Going Down #{inspect(reason)}: #{inspect(state)}")
    Logger.error("what is this....")
    :normal
  end

  @impl true
  def handle_info(:send_worker_state, %{server_id: server_id, worker_state: worker_state} = state) do
    PubSub.broadcast(
      @pubsub_server,
      "gameserver_id_#{server_id}",
      {:data, server_id, :worker_state, worker_state}
    )

    Process.send_after(self(), :send_worker_state, 5_000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:read_logline, %{queue: []} = state) do
    Logger.debug("#{state.short_name}: no new logline in queue!")

    {:noreply, state}
  end

  @impl true
  def handle_info(
        :read_logline,
        %{server_id: server_id, queue: [logline | rest], worker_state: worker_state} = state
      ) do
    old_len = get_in(worker_state, [:count])

    worker_state =
      worker_state
      |> put_in([:count], old_len - 1)
      |> put_in([:last_line], logline)
      |> put_in([:last_timestamp], DateTime.utc_now())

    [ts, message] = String.split(logline, ":", parts: 2)

    PubSub.broadcast(
      @pubsub_server,
      "gameserver_id_#{server_id}",
      {:data, server_id, :logline, %{ts: ts, message: message}}
    )

    ref = Process.send_after(self(), :read_logline, 1)

    state
    |> Map.put(:timer_ref, ref)
    |> Map.put(:worker_state, worker_state)
    |> Map.put(:queue, rest)
    |> LoglineMapper.map(logline)
    |> then(&{:noreply, &1})
  end

  @impl true
  def handle_info(whatever, state) do
    Logger.error("#{inspect(whatever)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:push, loglist},
        %{timer_ref: timer_ref, server_id: _server_id, queue: queue, worker_state: worker_state} =
          state
      ) do
    Logger.info("pushing #{length(loglist)} log_lines to #{state.name}-queue")
    if timer_ref, do: Process.cancel_timer(timer_ref)

    new_queue = queue ++ loglist

    worker_state = put_in(worker_state, [:count], length(new_queue))

    Map.put(state, :queue, new_queue)
    |> Map.put(:worker_state, worker_state)
    |> then(fn state ->
      ref = Process.send_after(self(), :read_logline, 1)

      Map.put(state, :timer_ref, ref)
      |> then(&{:noreply, &1})
    end)
  end
end
