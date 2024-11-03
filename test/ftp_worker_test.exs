defmodule ServerlogDaemon.FtpWorkerTest do
  @moduledoc false
  use ExUnit.Case
  # alias Phoenix.PubSub
  alias ServerlogDaemon.FtpWorker

  import Mock

  doctest FtpWorker

  @default_state %{
    address: %{
      host: {123, 124, 125, 126},
      port: 4711,
      user: ~c"username",
      password: ~c"password"
    },
    file_hash: "",
    log_hash: "",
    index: 666_666_666_666,
    worker: :worker_1_llw,
    server_id: "worker_1",
    timer_ref: nil,
    short_name: "w_1",
    name: :worker_1_ftp
  }

  # setup_with_mocks([
  #   {PubSub, [], broadcast: fn _pub_sub, _server_id, _data -> :ok end}
  # ]) do
  #   :ok
  # end

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

  describe "handle_info:load_logfile" do
    test_with_mock "errors @ load_logfile", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:error, :epath} end,
      close: fn "ftp_pid" -> :ok end do
      assert {:noreply, %{timer_ref: timer_ref} = state} =
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

      assert {:noreply, %{timer_ref: timer_ref} = state} =
               FtpWorker.handle_info(:load_logfile, state)

      assert Process.read_timer(timer_ref) >= 890
    end
    test_with_mock "all should run normally with changed file", :ftp,
      open: fn _host, _opts -> {:ok, "ftp_pid"} end,
      user: fn "ftp_pid", _user, _password -> :ok end,
      cd: fn "ftp_pid", ~c"/log" -> :ok end,
      recv_bin: fn "ftp_pid", ~c"server.log" -> {:ok, ~c"lskdjfsldfkjkos"} end,
      close: fn "ftp_pid" -> :ok end do
      state =
        Map.put(
          @default_state,
          :file_hash,
          "F888C5C3D764711351A96A144B4D051DE304E59912D2047E11FE55141457ED54EA0850B8F7B69A9B765E07C04E70149A370DD0142567BF6FB6924D0002C4D6CD"
        )

      assert {:noreply, %{timer_ref: timer_ref} = state} =
               FtpWorker.handle_info(:load_logfile, state)

      assert Process.read_timer(timer_ref) >= 890
    end
  end
end
