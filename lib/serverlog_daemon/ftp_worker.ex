defmodule ServerlogDaemon.FtpWorker do
  @moduledoc false
  use GenServer
  require Logger

  @file_path Application.compile_env(:serverlog_daemon, :file_path)

  @doc """
  Init the args.

  ## Examples

      iex> FtpWorker.init(%{})
      {:ok, %{}}

  """
  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :load_logfile, 500)

    {:ok, args}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: args.name)
  end

  @doc """
  Callback function which is called when the GenServer stops.

  ## Examples

      iex> FtpWorker.terminate(:broken, %{})
      :normal

  """
  @impl true
  def terminate(reason, state) do
    Logger.warning("terminate/2 callback @ ftp_worker")
    Logger.warning("Going Down #{reason}: #{inspect(state)}")
    :normal
  end

  @impl true
  def handle_info(:load_logfile, state) do
    case :timer.tc(fn -> load_logfile(state) end) do
      {time, {:ok, file}} ->
        if time > 500_000,
          do: Logger.warning("loading the file took much longer than expected: #{time} µs!")

        Logger.debug("#{state.short_name}: loaded file in #{time} µs!")

        calc_hash(file)
        |> process_logfile(file, state)
        |> then(fn state ->
          Process.send_after(self(), :load_logfile, 2_000)
          {:noreply, state}
        end)

      {time, {:error, error}} ->
        Logger.critical("got error #{inspect(error)} in #{time} µs")
        Process.send_after(self(), :load_logfile, 30_000)
        {:noreply, state}
    end
  end

  defp calc_hash(str) do
    :crypto.hash(:sha3_512, str)
    |> Base.encode16()
  end

  defp load_logfile(state) do
    case :ftp.open(state.address.host, port: state.address.port) do
      {:ok, pid} ->
        with :ok <- :ftp.user(pid, state.address.user, state.address.password),
             :ok <- :ftp.cd(pid, ~c"/log"),
             {:ok, file} <- :ftp.recv_bin(pid, ~c"server.log") do
          :ftp.close(pid)

          {:ok, :unicode.characters_to_binary(file, :latin1)}
        else
          {:error, error} ->
            :ftp.close(pid)
            Logger.error(inspect(error))
            {:error, error}

          whatelse ->
            Logger.error("whatelse: #{inspect(whatelse)}")
            :ftp.close(pid)
            {:error, whatelse}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp process_logfile(file_hash, _file, %{file_hash: state_file_hash} = state)
       when file_hash === state_file_hash do
    Logger.debug("file did not change, do nothing!")
    state
  end

  defp process_logfile(
         file_hash,
         file,
         %{file_hash: state_file_hash, index: state_index} = state
       ) do
    Logger.warning("process file, hash: #{file_hash}, state_hash: #{state_file_hash}")

    log =
      file
      |> String.replace(~r/(\r\n)/, "\n")
      |> String.replace(~r/\n(\D)/, " | \\g{1}")
      |> String.split("\n", trim: true)
      |> Enum.drop(-1)

    {old_lines, new_lines} = Enum.split(log, state_index)

    old_lines_hash = calc_hash(old_lines)
    log_hash = calc_hash(log)
    index = length(log)

    {path, filename, rows} = compare_lines(state, old_lines_hash, new_lines, log)

    write_file(path, filename, rows)

    Enum.each(state.worker_list, fn worker ->
      GenServer.cast(worker, {:push, rows})
    end)

    state
    |> Map.put(:path, filename)
    |> Map.put(:filename, filename)
    |> Map.put(:index, index)
    |> Map.put(:file_hash, file_hash)
    |> Map.put(:log_hash, log_hash)
  end

  def write_file(_path, _filename, _rows) when is_nil(@file_path) do
    Logger.warning("no file_path, no file!")
  end

  def write_file(path, filename, rows) do
    full_path = "#{String.replace_suffix(@file_path, "/", "")}/#{path}"
    File.mkdir_p("#{full_path}")

    File.write(
      "#{full_path}/#{filename}",
      "#{Enum.join(rows, "\n")}\n",
      [
        :append
      ]
    )
  end

  def compare_lines(state, old_hash, new_lines, _log) when old_hash == state.log_hash,
    do: {state.path, state.filename, new_lines}

  def compare_lines(state, _old_hash, _new_lines, log) do
    {path, file} = new_filename(state)
    filename = "#{path}/#{file}"
    log = ["#{DateTime.utc_now() |> DateTime.to_unix()}: +++ new file [#{filename}] +++" | log]
    {path, file, log}
  end

  defp new_filename(%{server_id: server_id}) do
    now = DateTime.utc_now()

    dts =
      "#{if now.day < 10, do: "0"}#{now.day}-" <>
        "#{if now.month < 10, do: "0"}#{now.month}-#{now.year}_" <>
        "#{if now.hour < 10, do: "0"}#{now.hour}-" <>
        "#{if now.minute < 10, do: "0"}#{now.minute}-" <>
        "#{if now.second < 10, do: "0"}#{now.second}"

    {"/#{server_id}", "#{dts}.log"}
  end
end
