defmodule ServerlogDaemon.LoglineWorkerTest do
  @moduledoc """
  The Tests for the LoglineWorker
  """
  use ExUnit.Case
  alias Phoenix.PubSub
  alias ServerlogDaemon.LoglineMapper
  alias ServerlogDaemon.LoglineWorker
  import Mock
  doctest ServerlogDaemon.LoglineWorker

  @default_state %{
    name: :test_logline_worker,
    timer_ref: nil,
    server_id: "123_a_server_id",
    short_name: "123",
    worker_state: %{
      last_line: "",
      last_timestamp: DateTime.from_unix!(0),
      count: 12
    },
    queue: [],
    state: %{conn_req: nil}
  }

  test "init" do
    assert {:ok, %{}} = LoglineWorker.init(%{})
  end

  test "start_link" do
    with_mock(GenServer, [], start_link: fn _module, _args, _name -> nil end) do
      LoglineWorker.start_link(%{name: "doof"})

      assert call_history(GenServer) == [
               {self(),
                {GenServer, :start_link,
                 [ServerlogDaemon.LoglineWorker, %{name: "doof"}, [name: "doof"]]}, nil}
             ]
    end
  end

  test "does nothing special @ termination" do
    assert :normal = LoglineWorker.terminate(:broken, %{})
  end

  test "sends worker state" do
    with_mocks([
      {PubSub, [], [broadcast: fn :pub_sub, _server_id, _data -> :ok end]}
    ]) do
      queue =
        1..42
        |> Enum.map(fn x ->
          "#{String.pad_leading(to_string(x), 10, "0")}: line ##{x}"
        end)

      state =
        @default_state
        |> Map.put(:queue, queue)

      LoglineWorker.handle_info(:send_worker_state, state)

      assert_called(
        PubSub.broadcast(
          :pub_sub,
          "gameserver_id_123_a_server_id",
          {:data, "123_a_server_id", :worker_state, state.worker_state}
        )
      )
    end
  end

  describe "handle_info:read_logline" do
    test "does nothing when queue is empty" do
      assert {:noreply, @default_state} = LoglineWorker.handle_info(:read_logline, @default_state)
    end

    test "pops logline from queue when !empty" do
      with_mocks([
        {PubSub, [], [broadcast: fn :pub_sub, _server_id, _data -> :ok end]},
        {LoglineMapper, [], [map: fn state, _line -> state end]}
      ]) do
        new_queue = [
          "1:this is a nice logline",
          "2:this is the logline after the nice logline"
        ]

        state =
          Map.put(@default_state, :queue, new_queue)

        assert {:noreply, new_state} = LoglineWorker.handle_info(:read_logline, state)

        assert_called(LoglineMapper.map(new_state, "1:this is a nice logline"))

        assert call_history(PubSub) == [
                 {self(),
                  {Phoenix.PubSub, :broadcast,
                   [
                     :pub_sub,
                     "gameserver_id_123_a_server_id",
                     {:data, "123_a_server_id", :logline,
                      %{message: "this is a nice logline", ts: "1"}}
                   ]}, :ok}
               ]
      end
    end
  end

  test "pushes loglines 2 queue @ handle_cast:push" do
    queue = [
      "1:this is a nice logline",
      "2:this is the logline after the nice logline"
    ]

    loglist = [
      "3:the 1st new line",
      "4:the line after the 1st new line"
    ]

    state =
      @default_state
      |> Map.put(:queue, queue)
      |> Map.put(:timer_ref, Process.send_after(self(), :read_logline, 50_000))

    assert {:noreply,
            %{
              name: :test_logline_worker,
              state: %{conn_req: nil},
              queue: [
                "1:this is a nice logline",
                "2:this is the logline after the nice logline",
                "3:the 1st new line",
                "4:the line after the 1st new line"
              ],
              timer_ref: timer_ref,
              server_id: "123_a_server_id",
              short_name: "123"
            }} = LoglineWorker.handle_cast({:push, loglist}, state)

    assert !is_nil(timer_ref)
  end
end
