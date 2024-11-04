defmodule ServerlogDaemon.LoglineMapper do
  @moduledoc false
  require Logger
  alias Phoenix.PubSub

  @pubsub_server Application.compile_env!(:serverlog_daemon, :pubsub_server)

  def new_state do
    %{conn_req: nil}
  end

  def map(state, logline) do
    [ts, line] = String.split(logline, ":", parts: 2)
    ts = String.to_integer(ts)
    map(state, ts, String.trim(line))
  end

  def map(%{server_id: server_id} = state, ts, message) do
    message = String.trim(message)

    cond do
      result = Regex.named_captures(~r/\+++ new file \[(?<filename>.*)] \+++/, message) ->
        %{"filename" => filename} = result

        Logger.warning("broadcast to gameserver_id_#{server_id}")

        PubSub.broadcast(
          @pubsub_server,
          "gameserver_id_#{server_id}",
          {:data, server_id, :new_event, %{ts: ts, filename: filename}}
        )

        state

      result = Regex.named_captures(~r/==ERR: Rejected driver, (?<reason>.*)/, message) ->
        %{"reason" => reason} = result

        Logger.warning("broadcast to gameserver_id_#{server_id}")

        PubSub.broadcast(
          @pubsub_server,
          "gameserver_id_#{server_id}",
          {:error, server_id, :rejected_driver, %{ts: ts, reason: reason}}
        )

        state

      true ->
        Logger.warning("ignore line: #{inspect({ts, message})}")
        state
    end
  end
end
