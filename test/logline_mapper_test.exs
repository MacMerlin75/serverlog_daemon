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

  describe "map" do
    test "does nothing with unknown logline" do
      assert @default_state == LoglineMapper.map(@default_state, "1234:nothing 2 do here")

      assert_not_called(PubSub.broadcast(:_, :_, :_))
    end

    test "broadcasts new event when a new file starts" do
      assert @default_state ==
               LoglineMapper.map(@default_state, "1234:--- new file [file_name.log] ---")

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :new_event,
           %{"ts" => 1234, "filename" => "file_name.log"}}
        )
      )
    end

    test "broadcasts number of clients online" do
      assert @default_state ==
               LoglineMapper.map(@default_state, "3929655: 5 client(s) online")

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :clients_online, %{"ts" => 3_929_655, "count" => "5"}}
        )
      )
    end

    test "broadcasts new connection" do
      assert @default_state ==
               LoglineMapper.map(
                 @default_state,
                 "2362349: Created connection with id 2"
               )

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :new_connection,
           %{
             "conn_id" => "2",
             "ts" => 2_362_349
           }}
        )
      )
    end

    test "broadcasts entrylist id" do
      assert @default_state ==
               LoglineMapper.map(
                 @default_state,
                 "1235249: Located entryListId 15 for connection 3 P7762436496629592476"
               )

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :connection_entrylist,
           %{
             "entrylist_id" => "15",
             "conn_id" => "3",
             "ts" => 1_235_249,
             "player_id" => "P7762436496629592476"
           }}
        )
      )
    end

    test "broadcasts entrylist id -1 when not found" do
      assert @default_state ==
               LoglineMapper.map(
                 @default_state,
                 "1235249: Located entryListId -1 for connection 3 P7762436496629592476"
               )

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :connection_entrylist,
           %{
             "entrylist_id" => "-1",
             "conn_id" => "3",
             "ts" => 1_235_249,
             "player_id" => "P7762436496629592476"
           }}
        )
      )
    end

    test "broadcasts connection request" do
      assert @default_state ==
               LoglineMapper.map(
                 @default_state,
                 "23237: New connection request: id 0  Bob Dockland | BOB P254153357560833119 on car model 25"
               )

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :connection_request,
           %{
             "name" => "Bob Dockland | BOB",
             "conn_id" => "0",
             "ts" => 23_237,
             "player_id" => "P254153357560833119",
             "car_model" => "25"
           }}
        )
      )
    end

    test "broadcasts new car connection" do
      assert @default_state ==
               LoglineMapper.map(
                 @default_state,
                 "1235249: Creating new car connection: carId 1002, carModel 16, raceNumber #673"
               )

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:data, @default_state.server_id, :connection_car,
           %{
             "race_number" => "673",
             "ts" => 1_235_249,
             "car_model" => "16",
             "car_id" => "1002"
           }}
        )
      )
    end

    test "broadcasts lost car" do
      assert @default_state ==
               LoglineMapper.map(
                 @default_state,
                 "3836619: Destroyed connection with id 3"
               )

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:error, @default_state.server_id, :lost_driver,
           %{
             "ts" => 3_836_619,
             "conn_id" => "3"
           }}
        )
      )
    end

    test "broadcasts error when rejected driver found" do
      assert @default_state ==
               LoglineMapper.map(
                 @default_state,
                 "27125589: ==ERR: Rejected driver, 2/3 track medals"
               )

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_#{@default_state.server_id}",
          {:error, @default_state.server_id, :rejected_driver,
           %{"ts" => 27_125_589, "reason" => "2/3 track medals"}}
        )
      )
    end
  end
end
