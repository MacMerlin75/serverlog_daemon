defmodule ServerlogDaemon.FtpWorkerTest do
  @moduledoc false
  use ExUnit.Case
  # alias Phoenix.PubSub
  alias ServerlogDaemon.FtpWorker

  import Mock

  doctest FtpWorker

  setup_with_mocks([
    {File, [:passthrough],
     [
       write: fn _path, _content, _modes -> :ok end,
       write!: fn _path, _content, _modes -> :ok end,
       mkdir_p: fn _path -> :ok end,
       mkdir_p!: fn _path -> :ok end
     ]}
  ]) do
    :ok
  end

  @default_state %{
    address: %{
      host: {123, 124, 125, 126},
      port: 4711,
      user: ~c"username",
      password: ~c"password"
    },
    file: "first_file.log",
    file_hash: "",
    log_hash: "",
    index: 666_666_666_666,
    worker: :worker_1_llw,
    server_id: "worker_1",
    timer_ref: nil,
    short_name: "w_1",
    name: :worker_1_ftp
  }

  test "init" do
    assert {:ok, args} = FtpWorker.init(@default_state)
    assert is_reference(args.timer_ref)

    assert Process.read_timer(args.timer_ref) >= 490
  end

  test "start_link" do
    assert {:ok, pid} = FtpWorker.start_link(%{name: :wtf})
    assert is_pid(pid)
  end

  describe "load_logfile" do
    test_with_mock "loads a file", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:ok, ~c"lskdjfsldfkj"} end,
      close: fn "ftp_pid" -> :ok end do
      assert {:ok, ~c"lskdjfsldfkj"} = FtpWorker.load_logfile(@default_state)
    end

    test_with_mock "returns error when ftp.open fails", :ftp,
      open: fn _host, _opts -> {:error, :ehost} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:ok, ~c"lskdjfsldfkj"} end,
      close: fn "ftp_pid" -> :ok end do
      assert {:error, :ehost} = FtpWorker.load_logfile(@default_state)
    end

    test_with_mock "returns error when ftp.user fails", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> {:error, :euser} end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:ok, ~c"lskdjfsldfkj"} end,
      close: fn "ftp_pid" -> :ok end do
      assert {:error, :euser} = FtpWorker.load_logfile(@default_state)
    end

    test_with_mock "returns error when ftp.cd fails", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> {:error, :epath} end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:ok, ~c"lskdjfsldfkj"} end,
      close: fn "ftp_pid" -> :ok end do
      assert {:error, :epath} = FtpWorker.load_logfile(@default_state)
    end

    test_with_mock "returns error when ftp.recv_bin fails", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:error, :epath} end,
      close: fn "ftp_pid" -> :ok end do
      assert {:error, :epath} = FtpWorker.load_logfile(@default_state)
    end

    test_with_mock "returns error when unexpected thing fails", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> :wtf end,
      close: fn "ftp_pid" -> :ok end do
      assert {:error, :wtf} = FtpWorker.load_logfile(@default_state)
    end
  end

  describe "prepare_log" do
    test "prepares a short logfile with index 15" do
      # File.ls("./test/testfiles")
      assert %{old_lines: old_lines, new_lines: new_lines, all_lines: all_lines} =
               File.read!("./test/testfiles/short_file.log")
               |> FtpWorker.prepare_log(15)

      assert old_lines.hash ==
               "DB7C3F3439226FF0FFFAFB9EFFD8243D0633C0157FF8DB91C92EC2C39758E90836E691756D79702D3FDB49B7DF4A7DFEEF00F814738C4EBADBD5D838D465E918"

      assert length(old_lines.lines) == 15

      assert new_lines.hash ==
               "4E8768287208503C2AF3E6035911C66522F1E4B513224E7C0C550F02C6467C0BAEFA215F5A720615E8446F77977C9EEB06AD586E29AD706283FB079A09CD6823"

      assert length(new_lines.lines) == 15

      assert all_lines.hash ==
               "B8BD1C656947F88145B5CC12D65567F69F60068B0A59055243BEDE2B877598AF9BE71E06C4C91CFF660D154D31E86847EB51E923B94603DF9AA295F3E823F777"

      assert length(all_lines.lines) == 30
    end

    test "prepares a short logfile with index 20" do
      # File.ls("./test/testfiles")
      assert %{old_lines: old_lines, new_lines: new_lines, all_lines: all_lines} =
               File.read!("./test/testfiles/short_file.log")
               |> FtpWorker.prepare_log(20)

      assert old_lines.hash ==
               "E268083912231C3B463A0A134886AD3BE6B8449E01A719E2EA92B41F0705B9BA7FF3BDDEE2F76DD27D207147FCE9B62ACF0304B46CBEA48B8A60E4B87A719B81"

      assert length(old_lines.lines) == 20

      assert new_lines.hash ==
               "42F76CBAC5C6904A387A66BC9D92234E2FB82294FF734A45C0A61E409544C1437171490D53D2B68C10809EEC821A965B79293A6D6515CAE1E1F8360C53E43CD6"

      assert length(new_lines.lines) == 10

      assert all_lines.hash ==
               "B8BD1C656947F88145B5CC12D65567F69F60068B0A59055243BEDE2B877598AF9BE71E06C4C91CFF660D154D31E86847EB51E923B94603DF9AA295F3E823F777"

      assert length(all_lines.lines) == 30
    end
  end

  describe "process_logfile" do
    test "use old filename when new lines are appended" do
      state =
        @default_state
        |> Map.put(:index, 20)
        |> Map.put(
          :log_hash,
          "E268083912231C3B463A0A134886AD3BE6B8449E01A719E2EA92B41F0705B9BA7FF3BDDEE2F76DD27D207147FCE9B62ACF0304B46CBEA48B8A60E4B87A719B81"
        )

      file = File.read!("./test/testfiles/short_file.log")

      assert %{
               index: 30,
               name: :worker_1_ftp,
               file: "first_file.log",
               address: %{
                 port: 4711,
                 user: ~c"username",
                 host: {123, 124, 125, 126},
                 password: ~c"password"
               },
               worker: :worker_1_llw,
               timer_ref: nil,
               short_name: "w_1",
               server_id: "worker_1",
               file_hash:
                 "E268083912231C3B463A0A134886AD3BE6B8449E01A719E2EA92B41F0705B9BA7FF3BDDEE2F76DD27D207147FCE9B62ACF0304B46CBEA48B8A60E4B87A719B81",
               log_hash:
                 "B8BD1C656947F88145B5CC12D65567F69F60068B0A59055243BEDE2B877598AF9BE71E06C4C91CFF660D154D31E86847EB51E923B94603DF9AA295F3E823F777"
             } =
               FtpWorker.process_logfile(
                 state,
                 "E268083912231C3B463A0A134886AD3BE6B8449E01A719E2EA92B41F0705B9BA7FF3BDDEE2F76DD27D207147FCE9B62ACF0304B46CBEA48B8A60E4B87A719B81",
                 file
               )

      assert called(File.write("/tmp/worker_1/first_file.log", :_, [:append]))
    end
  end

  describe "new_filename" do
    test "knits a nice new filename" do
      date = DateTime.new!(~D[2222-02-22], ~T[22:22:22.222], "Etc/UTC")
      assert "22-02-2222_22-22-22.log" == FtpWorker.new_filename(date)
    end
  end

  describe "write_file" do
  end

  describe "handle_info:load_logfile" do
    test_with_mock "errors @ load_logfile", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:error, :epath} end,
      close: fn "ftp_pid" -> :ok end do
      assert {:noreply, %{timer_ref: timer_ref}} =
               FtpWorker.handle_info(:load_logfile, @default_state)

      assert Process.read_timer(timer_ref) >= 9_990
    end

    test_with_mock "all should run normally when file didn't change", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:ok, ~c"lskdjfsldfkj"} end,
      close: fn "ftp_pid" -> :ok end do
      state =
        Map.put(
          @default_state,
          :file_hash,
          "F888C5C3D764711351A96A144B4D051DE304E59912D2047E11FE55141457ED54EA0850B8F7B69A9B765E07C04E70149A370DD0142567BF6FB6924D0002C4D6CD"
        )

      assert {:noreply, %{timer_ref: timer_ref}} =
               FtpWorker.handle_info(:load_logfile, state)

      assert Process.read_timer(timer_ref) >= 890
    end

    # , [{:ftp,

    #  do}, {DateTime, [:passthrough], []}]

    test "all should run normally with changed file" do
      with_mocks([
        {:ftp, [],
         [
           open: fn _host, _opts -> {:ok, "ftp_pid"} end,
           user: fn "ftp_pid", _user, _password -> :ok end,
           cd: fn "ftp_pid", ~c"/log" -> :ok end,
           recv_bin: fn "ftp_pid", ~c"server.log" -> {:ok, ~c"lskdjfsldfkjkos"} end,
           close: fn "ftp_pid" -> :ok end
         ]},
        {DateTime, [:passthrough],
         [
           utc_now: fn -> ~U[2024-11-04 09:19:00.943018Z] end
         ]}
      ]) do
        state =
          Map.put(
            @default_state,
            :file_hash,
            "F888C5C3D764711351A96A144B4D051DE304E59912D2047E11FE55141457ED54EA0850B8F7B69A9B765E07C04E70149A370DD0142567BF6FB6924D0002C4D6CD"
          )

        assert {:noreply, %{timer_ref: timer_ref}} =
                 FtpWorker.handle_info(:load_logfile, state)

        assert called(File.write("/tmp/worker_1/04-11-2024_09-19-00.log", :_, [:append]))

        assert Process.read_timer(timer_ref) >= 890
      end
    end
  end
end
