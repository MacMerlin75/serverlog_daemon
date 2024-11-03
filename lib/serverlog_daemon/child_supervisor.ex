defmodule ServerlogDaemon.ChildSupervisor do
  @moduledoc false
  use Supervisor
  require Logger

  @impl true
  def init(init_arg) do
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
              worker: String.to_atom("#{init_arg.id}_llw"),
              server_id: init_arg.id,
              timer_ref: nil,
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

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_link(init_arg) do
    child_id = String.to_atom(init_arg.id)

    Supervisor.start_link(__MODULE__, init_arg, name: child_id)
  end
end
