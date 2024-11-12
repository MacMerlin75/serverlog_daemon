defmodule ServerlogDaemon.FtpWorker do
  @moduledoc false
  use GenServer
  require Logger

  @file_path Application.compile_env(:serverlog_daemon, :file_path) || "./logs/"
  @file_load_warning_timeout Application.compile_env(
                               :serverlog_daemon,
                               :file_load_warning_timeout
                             ) || 500_000

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    timer_ref = Process.send_after(self(), :load_logfile, 500)

    {:ok, Map.put(args, :timer_ref, timer_ref)}
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
      {time, {:ok, raw_file}} ->
        if time > @file_load_warning_timeout,
          do:
            Logger.warning(
              "loading the file took much longer than expected (#{@file_load_warning_timeout}): #{time} µs!"
            )

        Logger.debug("#{state.short_name}: loaded file in #{time} µs!")
        file = :unicode.characters_to_binary(raw_file, :latin1)
        file_hash = calc_hash(file)

        state
        |> process_logfile(file_hash, file)
        |> then(fn state ->
          timer_ref = Process.send_after(self(), :load_logfile, 1_000)
          {:noreply, Map.put(state, :timer_ref, timer_ref)}
        end)

      # {:noreply, state}

      {time, {:error, error}} ->
        Logger.critical("got error #{inspect(error)} in #{time} µs")
        timer_ref = Process.send_after(self(), :load_logfile, 10_000)
        {:noreply, Map.put(state, :timer_ref, timer_ref)}
    end
  end

  defp calc_hash(str) do
    :crypto.hash(:sha3_512, str)
    |> Base.encode16()
  end

  @doc false
  def load_logfile(state) do
    case :ftp.open(state.address.host, port: state.address.port) do
      {:ok, pid} ->
        with :ok <- :ftp.user(pid, state.address.user, state.address.password),
             :ok <- :ftp.cd(pid, ~c"/log"),
             {:ok, file} <- :ftp.recv_bin(pid, ~c"server.log") do
          :ftp.close(pid)

          {:ok, file}
        else
          {:error, error} ->
            :ftp.close(pid)
            Logger.error(inspect(error))
            {:error, error}

          whatelse ->
            Logger.critical("unexpected error: #{inspect(whatelse)}")
            :ftp.close(pid)
            {:error, whatelse}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @doc false
  def prepare_log(logfile, idx) do
    all_lines =
      logfile
      # remove the \r
      |> String.replace(~r/(\r\n)/, "\n")
      # fix the issue when a logline includes a \n so the next line doesn't start with the timestamp
      |> String.replace(~r/\n(\D)/, " | \\g{1}")
      |> String.split("\n", trim: true)
      # we omit the last line to ensure that we only process complete lines
      |> Enum.drop(-1)

    {old_lines, new_lines} = Enum.split(all_lines, idx)

    %{
      old_lines: %{lines: old_lines, hash: calc_hash(old_lines)},
      new_lines: %{lines: new_lines, hash: calc_hash(new_lines)},
      all_lines: %{lines: all_lines, hash: calc_hash(all_lines), index: length(all_lines)}
    }
  end

  @doc false
  def process_logfile(state, file_hash, file)

  def process_logfile(%{file_hash: state_file_hash} = state, file_hash, _file)
      when file_hash === state_file_hash do
    Logger.debug("file did not change, do nothing!")
    state
  end

  def process_logfile(
        %{index: state_index, log_hash: state_log_hash, worker: worker, server_id: server_id} =
          state,
        file_hash,
        file
      ) do
    %{old_lines: old_lines, new_lines: new_lines, all_lines: all_lines} =
      prepare_log(file, state_index)

    {file, lines_2_process} =
      if old_lines.hash == state_log_hash do
        {state.file, new_lines.lines}
      else
        filename = new_filename(DateTime.utc_now())
        full_path = "#{String.replace_suffix(@file_path, "/", "")}/#{server_id}"

        lines = [
          "#{DateTime.utc_now() |> DateTime.to_unix()}: --- new file [#{full_path}/#{filename}] ---"
          | all_lines.lines
        ]

        {filename, lines}
      end

    GenServer.cast(worker, {:push, lines_2_process})

    write_file(state, file, lines_2_process)

    state
    |> Map.put(:file, file)
    |> Map.put(:index, all_lines.index)
    |> Map.put(:file_hash, file_hash)
    |> Map.put(:log_hash, all_lines.hash)
  end

  def write_file(%{server_id: server_id}, filename, rows) do
    full_path = "#{String.replace_suffix(@file_path, "/", "")}/#{server_id}"
    File.mkdir_p("#{full_path}")

    File.write(
      "#{full_path}/#{filename}",
      "#{Enum.join(rows, "\n")}\n",
      [
        :append
      ]
    )
  end

  @doc false
  def new_filename(dt) do
    "#{if dt.day < 10, do: "0"}#{dt.day}-" <>
      "#{if dt.month < 10, do: "0"}#{dt.month}-#{dt.year}_" <>
      "#{if dt.hour < 10, do: "0"}#{dt.hour}-" <>
      "#{if dt.minute < 10, do: "0"}#{dt.minute}-" <>
      "#{if dt.second < 10, do: "0"}#{dt.second}" <>
      ".log"
  end
end
