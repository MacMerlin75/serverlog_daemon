defmodule ServerlogDaemon.StateWorkerTest do
  @moduledoc false
  use ExUnit.Case
  alias Phoenix.PubSub
  alias ServerlogDaemon.StateWorker

  import Mock

  doctest ServerlogDaemon.StateWorker

  test "init" do
    with_mock(PubSub, [], subscribe: fn :pub_sub, _topic -> :ok end) do
      assert {:ok, %{}} = StateWorker.init(%{})
      assert_called(PubSub.subscribe(:pub_sub, "gameserver"))
    end
  end

  test "start_link" do
    with_mock(GenServer, [], start_link: fn _module, _args, _name -> nil end) do
      StateWorker.start_link(nil)

      assert_called(GenServer.start_link(StateWorker, :_, name: :state_worker))
    end
  end

  describe "process gameserver" do
    test "does nothing when gameserver didn't change" do
      state = %{
        "123_gs_id" => %{
          gameserver: %{
            id: "123_gs_id",
            ip: "1.2.3.4",
            port: "4711",
            name: "nice gameserver",
            short_name: "niga",
            description: "what the server",
            hidden: false,
            status: :active,
            user: "ftp_user",
            password: "ftp_password"
          }
        }
      }

      assert {:noreply, state} ==
               StateWorker.handle_info(
                 {:gameserver,
                  %{
                    id: "123_gs_id",
                    ip: "1.2.3.4",
                    port: "4711",
                    name: "nice gameserver",
                    short_name: "niga",
                    description: "what the server",
                    hidden: false,
                    status: :active,
                    user: "ftp_user",
                    password: "ftp_password"
                  }},
                 state
               )
    end

    test "does nothing when gameserver not @ state but inactive" do
      state = %{}

      assert {:noreply, state} ==
               StateWorker.handle_info(
                 {:gameserver,
                  %{
                    id: "123_gs_id",
                    ip: "1.2.3.4",
                    port: "4711",
                    name: "nice gameserver",
                    short_name: "niga",
                    description: "what the server",
                    hidden: false,
                    status: :inactive,
                    user: "ftp_user",
                    password: "ftp_password"
                  }},
                 state
               )
    end

    test "does nothing when gameserver not @ state but deleted" do
      state = %{}

      assert {:noreply, state} ==
               StateWorker.handle_info(
                 {:gameserver,
                  %{
                    id: "123_gs_id",
                    ip: "1.2.3.4",
                    port: "4711",
                    name: "nice gameserver",
                    short_name: "niga",
                    description: "what the server",
                    hidden: false,
                    status: :deleted,
                    user: "ftp_user",
                    password: "ftp_password"
                  }},
                 state
               )
    end

    test "removes gameserver from state after successfully stop it" do
      with_mock(DynamicSupervisor, [],
        terminate_child: fn ServerlogDaemon.DynamicSupervisor, _pid -> :ok end
      ) do
        state = %{
          "123_gs_id" => %{
            pid: :a_pid,
            gameserver: %{
              id: "123_gs_id",
              ip: "1.2.3.4",
              port: "4711",
              name: "nice gameserver",
              short_name: "niga",
              description: "what the server",
              hidden: false,
              status: :active,
              user: "ftp_user",
              password: "ftp_password"
            }
          }
        }

        assert {:noreply, %{}} ==
                 StateWorker.handle_info(
                   {:gameserver,
                    %{
                      id: "123_gs_id",
                      ip: "1.2.3.4",
                      port: "4711",
                      name: "nice gameserver",
                      short_name: "niga",
                      description: "what the server",
                      hidden: false,
                      status: :inactive,
                      user: "ftp_user",
                      password: "ftp_password"
                    }},
                   state
                 )
      end
    end

    test "removes gameserver from state when process wasn't found" do
      with_mock(DynamicSupervisor, [],
        terminate_child: fn ServerlogDaemon.DynamicSupervisor, _pid -> {:error, :not_found} end
      ) do
        state = %{
          "123_gs_id" => %{
            pid: :a_pid,
            gameserver: %{
              id: "123_gs_id",
              ip: "1.2.3.4",
              port: "4711",
              name: "nice gameserver",
              short_name: "niga",
              description: "what the server",
              hidden: false,
              status: :active,
              user: "ftp_user",
              password: "ftp_password"
            }
          }
        }

        assert {:noreply, %{}} ==
                 StateWorker.handle_info(
                   {:gameserver,
                    %{
                      id: "123_gs_id",
                      ip: "1.2.3.4",
                      port: "4711",
                      name: "nice gameserver",
                      short_name: "niga",
                      description: "what the server",
                      hidden: false,
                      status: :inactive,
                      user: "ftp_user",
                      password: "ftp_password"
                    }},
                   state
                 )
      end
    end

    test "gameserver not at state? Adds gameserver to state after successfully start process" do
      with_mocks([
        {DynamicSupervisor, [],
         [start_child: fn ServerlogDaemon.DynamicSupervisor, _spec -> {:ok, "sv_pid"} end]},
        {:ftp, [],
         [
           open: fn _ip, _opt -> {:ok, "ftp_pid"} end,
           user: fn _pid, _user, _password -> :ok end,
           ls: fn _pid, _path -> {:ok, ""} end,
           close: fn _pid -> :ok end
         ]}
      ]) do
        state = %{}

        assert {:noreply,
                %{
                  "123_gs_id" => %{
                    pid: "sv_pid",
                    gameserver: %{
                      hidden: false,
                      id: "123_gs_id",
                      name: "nice gameserver",
                      port: "4711",
                      status: :active,
                      user: "ftp_user",
                      ip: "1.2.3.4",
                      description: "what the server",
                      password: "ftp_password",
                      short_name: "niga"
                    }
                  }
                }} ==
                 StateWorker.handle_info(
                   {:gameserver,
                    %{
                      id: "123_gs_id",
                      ip: "1.2.3.4",
                      port: "4711",
                      name: "nice gameserver",
                      short_name: "niga",
                      description: "what the server",
                      hidden: false,
                      status: :active,
                      user: "ftp_user",
                      password: "ftp_password"
                    }},
                   state
                 )
      end
    end

    test "give up when ftp.open fails too often" do
      with_mocks([
        {DynamicSupervisor, [],
         [start_child: fn ServerlogDaemon.DynamicSupervisor, _spec -> {:ok, "sv_pid"} end]},
        {:ftp, [],
         [
           open: fn _ip, _opt -> {:error, "open failed"} end,
           user: fn _pid, _user, _password -> :ok end,
           ls: fn _pid, _path -> {:ok, ""} end,
           close: fn _pid -> :ok end
         ]}
      ]) do
        state = %{}

        assert {:noreply, %{}} ==
                 StateWorker.handle_info(
                   {:gameserver,
                    %{
                      id: "123_gs_id",
                      ip: "1.2.3.4",
                      port: "4711",
                      name: "nice gameserver",
                      short_name: "niga",
                      description: "what the server",
                      hidden: false,
                      status: :active,
                      user: "ftp_user",
                      password: "ftp_password"
                    }},
                   state
                 )
      end
    end

    test "give up when ftp.user fails too often" do
      with_mocks([
        {DynamicSupervisor, [],
         [start_child: fn ServerlogDaemon.DynamicSupervisor, _spec -> {:ok, "sv_pid"} end]},
        {:ftp, [],
         [
           open: fn _ip, _opt -> {:ok, "ftp_pid_5"} end,
           user: fn _pid, _user, _password -> {:error, :unk_user} end,
           ls: fn _pid, _path -> {:ok, ""} end,
           close: fn _pid -> :ok end
         ]}
      ]) do
        state = %{}

        assert {:noreply, %{}} ==
                 StateWorker.handle_info(
                   {:gameserver,
                    %{
                      id: "123_gs_id",
                      ip: "1.2.3.4",
                      port: "4711",
                      name: "nice gameserver",
                      short_name: "niga",
                      description: "what the server",
                      hidden: false,
                      status: :active,
                      user: "ftp_user",
                      password: "ftp_password"
                    }},
                   state
                 )

        assert_called(:ftp.close("ftp_pid_5"))
      end
    end

    test "stops and restarts process when gameserver data did change" do
      with_mocks([
        {DynamicSupervisor, [],
         [
           terminate_child: fn ServerlogDaemon.DynamicSupervisor, _pid -> :ok end,
           start_child: fn ServerlogDaemon.DynamicSupervisor, _spec -> {:ok, "sv_new_pid"} end
         ]},
        {:ftp, [],
         [
           open: fn _ip, _opt -> {:ok, "ftp_pid_5"} end,
           user: fn _pid, _user, _password -> :ok end,
           ls: fn _pid, _path -> {:ok, ""} end,
           close: fn _pid -> :ok end
         ]}
      ]) do
        state = %{
          "123_gs_id" => %{
            pid: "sv_new_pid",
            gameserver: %{
              hidden: false,
              id: "123_gs_id",
              name: "nice gameserver",
              port: "4711",
              status: :active,
              user: "ftp_user",
              ip: "1.2.3.4",
              description: "what the server",
              password: "ftp_password",
              short_name: "niga"
            }
          }
        }

        assert {:noreply,
                %{
                  "123_gs_id" => %{
                    pid: "sv_new_pid",
                    gameserver: %{
                      hidden: false,
                      id: "123_gs_id",
                      name: "nice gameserver",
                      port: "4711",
                      status: :active,
                      user: "ftp_user",
                      ip: "1.2.3.5",
                      description: "what the server",
                      password: "ftp_password",
                      short_name: "niga"
                    }
                  }
                }} ==
                 StateWorker.handle_info(
                   {:gameserver,
                    %{
                      id: "123_gs_id",
                      ip: "1.2.3.5",
                      port: "4711",
                      name: "nice gameserver",
                      short_name: "niga",
                      description: "what the server",
                      hidden: false,
                      status: :active,
                      user: "ftp_user",
                      password: "ftp_password"
                    }},
                   state
                 )

        assert_called(:ftp.close("ftp_pid_5"))
      end
    end

    test "update state if process already running" do
      with_mocks([
        {DynamicSupervisor, [],
         [
           terminate_child: fn ServerlogDaemon.DynamicSupervisor, _pid -> :ok end,
           start_child: fn ServerlogDaemon.DynamicSupervisor, _spec ->
             {:error, {:already_started, "sv_old_pid"}}
           end
         ]},
        {:ftp, [],
         [
           open: fn _ip, _opt -> {:ok, "ftp_pid_5"} end,
           user: fn _pid, _user, _password -> :ok end,
           ls: fn _pid, _path -> {:ok, ""} end,
           close: fn _pid -> :ok end
         ]}
      ]) do
        state = %{}

        assert {:noreply,
                %{
                  "123_gs_id" => %{
                    pid: "sv_old_pid",
                    gameserver: %{
                      hidden: false,
                      id: "123_gs_id",
                      name: "nice gameserver",
                      port: "4711",
                      status: :active,
                      user: "ftp_user",
                      ip: "1.2.3.5",
                      description: "what the server",
                      password: "ftp_password",
                      short_name: "niga"
                    }
                  }
                }} ==
                 StateWorker.handle_info(
                   {:gameserver,
                    %{
                      id: "123_gs_id",
                      ip: "1.2.3.5",
                      port: "4711",
                      name: "nice gameserver",
                      short_name: "niga",
                      description: "what the server",
                      hidden: false,
                      status: :active,
                      user: "ftp_user",
                      password: "ftp_password"
                    }},
                   state
                 )
      end
    end
  end
end
