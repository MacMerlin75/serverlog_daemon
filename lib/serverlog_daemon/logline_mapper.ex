defmodule ServerlogDaemon.LoglineMapper do
  @moduledoc false
  require Logger
  alias Phoenix.PubSub

  @pubsub_server Application.compile_env!(:serverlog_daemon, :pubsub_server)

  @pattern_list [
    {"--- new file \\[<filename>\\] ---", :data, :new_event},
    {"<count> client\\(s\\) online", :data, :clients_online},
    {"Created connection with id <conn_id>", :data, :new_connection},
    {"Located entryListId <entrylist_id> for connection <conn_id> <player_id>", :data,
     :connection_entrylist},
    {"New connection request: id <conn_id>  <name> <player_id> on car model <car_model>", :data,
     :connection_request},
    {"Creating new car connection: carId <car_id>, carModel <car_model>, raceNumber #<race_number>",
     :data, :connection_car},
    {"==ERR: Rejected driver, <reason>", :error, :rejected_driver},
    {"Destroyed connection with id <conn_id>", :error, :lost_driver}
  ]

  @pattern Enum.map(@pattern_list, fn {reg_x_str, type, what} ->
             reg_x =
               String.replace(
                 reg_x_str,
                 [
                   "<conn_id>",
                   "<count>",
                   "<entrylist_id>",
                   "<filename>",
                   "<player_id>",
                   "<name>",
                   "<car_model>",
                   "<car_id>",
                   "<race_number>",
                   "<reason>"
                 ],
                 fn
                   "<conn_id>" -> "(?<conn_id>\\d+)"
                   "<count>" -> "(?<count>\\d+)"
                   "<entrylist_id>" -> "(?<entrylist_id>-?\\d+)"
                   "<player_id>" -> "(?<player_id>\\S+)"
                   "<filename>" -> "(?<filename>.+)"
                   "<name>" -> "(?<name>.+)"
                   "<car_model>" -> "(?<car_model>\\d+)"
                   "<car_id>" -> "(?<car_id>\\d{4})"
                   "<race_number>" -> "(?<race_number>\\d+)"
                   "<reason>" -> "(?<reason>.+)"
                 end
               )
               |> Regex.compile!()

             {reg_x, type, what}
           end)

  def map(state, logline) do
    [ts, line] = String.split(logline, ":", parts: 2)
    ts = String.to_integer(ts)
    map(state, ts, String.trim(line))
  end

  defp task(pat, message) do
    {reg_x, type, what} = pat

    if result = Regex.named_captures(reg_x, message) do
      {result, type, what}
    else
      nil
    end
  end

  def map(%{server_id: server_id} = state, ts, message) do
    @pattern
    |> Enum.map(fn pat ->
      Task.async(fn ->
        task(pat, message)
      end)
    end)
    |> Enum.map(&Task.await/1)
    |> Enum.filter(& &1)
    |> then(fn res ->
      case length(res) do
        0 ->
          Logger.debug("not found: #{message}")

        # Logger.error(inspect(@pattern))
        1 ->
          [{result, type, what}] = res

          result =
            result
            |> Map.put("ts", ts)

          PubSub.broadcast(
            @pubsub_server,
            "gameserver_id_#{server_id}",
            {type, server_id, what, result}
          )

        _ ->
          Logger.critical("more than 1 found!")
      end

      state
    end)
  end
end
