defmodule ServerlogDaemon.LoglineMapperTest do
  @moduledoc false
  use ExUnit.Case
  alias Phoenix.PubSub
  alias ServerlogDaemon.LoglineMapper

  import Mock

  doctest LoglineMapper

  @default_state %{
    name: UUID.uuid4() |> String.to_atom(),
    timer_ref: nil,
    server_id: UUID.uuid4(),
    short_name: "ser_ver",
    queue: [],
    state: %{conn_req: nil}
  }

  setup_with_mocks([
    {PubSub, [], broadcast: fn _pub_sub, _server_id, _data -> :ok end}
  ]) do
    :ok
  end

  test "get a new state" do
    assert %{conn_req: nil} = LoglineMapper.new_state()
  end

  describe "map" do
    test "does nothing with unknown logline" do
      assert @default_state == LoglineMapper.map(@default_state, "1234:nothing 2 do here")

      assert_not_called(PubSub.broadcast(:_, :_, :_))
    end

    test "broadcasts new event when a new file starts" do
      assert @default_state ==
               LoglineMapper.map(@default_state, "1234:+++ new file [file_name.log] +++")

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :new_event, %{ts: 1234, filename: "file_name.log"}}
        )
      )
    end

    test "broadcasts error when rejected driver found" do
      assert @default_state ==
               LoglineMapper.map(@default_state, "27125589: ==ERR: Rejected driver, 2/3 track medals")

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:error, @default_state.server_id, :rejected_driver, %{ts: 27_125_589, reason: "2/3 track medals"}}
        )
      )
    end
  end
end
