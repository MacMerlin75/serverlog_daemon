defmodule ServerlogDaemon.ChildSupervisorTest do
  @moduledoc false
  use ExUnit.Case
  alias ServerlogDaemon.ChildSupervisor

  import Mock

  doctest ChildSupervisor

  test "init" do
    with_mock(Supervisor, [], init: fn _children, strategy: :one_for_one -> {:ok, "s_pid"} end) do
      init_arg = %{
        host: {1, 2, 3, 4},
        port: 12345,
        user: ~c"user",
        password: ~c"password",
        id: "unique_id",
        name: :unique_id,
        short_name: "game_serv"
      }

      children = [
        %{
          id: String.to_atom("#{init_arg.id}_ftp"),
          start: {
            ServerlogDaemon.FtpWorker,
            :start_link,
            [
              %{
                address: %{
                  host: init_arg.host,
                  port: init_arg.port,
                  user: init_arg.user,
                  password: init_arg.password
                },
                file_hash: "",
                log_hash: "",
                index: 666_666_666_666,
                worker_list: [
                  String.to_atom("#{init_arg.id}_llw")
                ],
                server_id: init_arg.id,
                short_name: init_arg.short_name,
                name: "#{init_arg.id}_ftp" |> String.to_atom()
              }
            ]
          }
        },
        %{
          id: String.to_atom("#{init_arg.id}_llw"),
          start: {
            ServerlogDaemon.LoglineWorker,
            :start_link,
            [
              %{
                name: "#{init_arg.id}_llw" |> String.to_atom(),
                timer_ref: nil,
                server_id: init_arg.id,
                short_name: init_arg.short_name,
                queue: [],
                state: %{conn_req: nil}
              }
            ]
          }
        }
      ]

      assert {:ok, "s_pid"} = ChildSupervisor.init(init_arg)
      assert_called(Supervisor.init(children, strategy: :one_for_one))
    end
  end

  test "start_link" do
    with_mock(Supervisor, [], start_link: fn _module, _args, _opts -> nil end) do
      init_arg = %{id: "a_nice_id"}
      ChildSupervisor.start_link(init_arg)

      assert_called(Supervisor.start_link(ChildSupervisor, init_arg, name: :a_nice_id))
    end
  end
end
