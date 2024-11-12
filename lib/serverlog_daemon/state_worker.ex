defmodule ServerlogDaemon.StateWorker do
  @moduledoc false
  alias Phoenix.PubSub

  @pubsub_server Application.compile_env!(:serverlog_daemon, :pubsub_server)
  @start_max_retry Application.compile_env(:serverlog_daemon, :start_max_retry) || 5

  require Logger
  use GenServer
  @impl true
  def init(_args) do
    PubSub.subscribe(@pubsub_server, "gameserver")
    {:ok, %{}}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: :state_worker)
  end

  @impl true
  def handle_info({:gameserver, gameserver}, state) do
    state_gameserver = get_in(state, [gameserver.id, :gameserver])

    state
    |> process_gameserver(gameserver, state_gameserver)
    |> then(&{:noreply, &1})
  end

  defp process_gameserver(state, gameserver, state_gameserver)
       when state_gameserver === gameserver do
    Logger.info("Gameserver didn't change, nothing 2 do!")
    state
  end

  defp process_gameserver(state, %{status: status}, state_gameserver)
       when is_nil(state_gameserver) and status in [:inactive, :deleted] do
    Logger.info("gameserver not @ state, but also not active. Do nothing!")
    state
  end

  defp process_gameserver(state, %{status: status} = gameserver, _state_gameserver)
       when status in [:inactive, :deleted] do
    pid = get_in(state, [gameserver.id, :pid])

    stop_gameserver_process(state, gameserver, pid)
  end

  defp process_gameserver(state, gameserver, state_gameserver) when is_nil(state_gameserver) do
    Logger.info("gameserver not @ state, start process now!")
    start_gameserver_process(state, gameserver)
  end

  defp process_gameserver(state, gameserver, _state_gameserver) do
    pid = get_in(state, [gameserver.id, :pid])
    state_gameserver = get_in(state, [gameserver.id, :gameserver])

    gs_root = Map.take(gameserver, [:ip, :port, :short_name, :user, :password])
    state_gs_root = Map.take(state_gameserver, [:ip, :port, :short_name, :user, :password])

    if gs_root != state_gs_root do
      Logger.debug("OK, stop -> start")

      stop_gameserver_process(state, gameserver, pid)
      |> start_gameserver_process(gameserver)
    else
      Logger.debug("root did not change, do nothing")
      state
    end
  end

  # defp stop_gameserver_process(state, _gameserver, nil), do: state

  defp stop_gameserver_process(state, gameserver, pid) do
    Logger.debug("try 2 stop process #{inspect(pid)}")

    case DynamicSupervisor.terminate_child(ServerlogDaemon.DynamicSupervisor, pid) do
      :ok ->
        Map.delete(state, gameserver.id)

      {:error, :not_found} ->
        Logger.debug("process not found? Ignore that …")
        Map.delete(state, gameserver.id)
    end
  end

  defp check_server(ip, gameserver) do
    address = %{
      host: ip,
      port: gameserver.port,
      user: ~c"#{gameserver.user}",
      password: ~c"#{gameserver.password}"
    }

    case :ftp.open(ip, port: address.port) do
      {:ok, pid} ->
        with :ok <- :ftp.user(pid, address.user, address.password),
             {:ok, _root_lst} <- :ftp.ls(pid, ~c"/"),
             {:ok, _log_list} <- :ftp.ls(pid, ~c"log") do
          :ftp.close(pid)

          :ok
        else
          {:error, error} ->
            :ftp.close(pid)
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp start_gameserver_process(state, gameserver, tries \\ 0)

  defp start_gameserver_process(state, _gameserver, tries) when tries >= @start_max_retry do
    Logger.critical("tried #{tries} times 2 start process, give up now!")
    state
  end

  # defp start_gameserver_process(state, %{status: status} = gameserver, _tries)
  #      when status in [:inactive, :deleted] do
  #   Logger.error("gameserver not active, no process needed")
  #   # Map.put(state, gameserver.id, %{gameserver: gameserver, pid: nil})
  #   state
  # end

  defp start_gameserver_process(state, gameserver, tries) do
    with {:ok, ip} <- :inet.parse_address(~c"#{gameserver.ip}"),
         :ok <- check_server(ip, gameserver),
         {:ok, pid} <-
           DynamicSupervisor.start_child(
             ServerlogDaemon.DynamicSupervisor,
             knit_spec(gameserver, ip)
           ) do
      Map.put(state, gameserver.id, %{gameserver: gameserver, pid: pid})
    else
      {:error, {:already_started, pid}} ->
        Logger.warning("process already started? Update state …")
        Map.put(state, gameserver.id, %{gameserver: gameserver, pid: pid})

      # stop_gameserver_process(state, gameserver, pid)

      whatelse ->
        Logger.critical(inspect(whatelse))
        start_gameserver_process(state, gameserver, tries + 1)
    end
  end

  defp knit_spec(gameserver, ip) do
    {ServerlogDaemon.ChildSupervisor,
     %{
       host: ip,
       port: gameserver.port,
       user: ~c"#{gameserver.user}",
       password: ~c"#{gameserver.password}",
       id: gameserver.id,
       name: "#{gameserver.id}" |> String.to_atom(),
       short_name: gameserver.short_name |> String.replace(~r/\W+/, "_")
     }}
  end
end
