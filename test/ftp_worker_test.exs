defmodule ServerlogDaemon.FtpWorkerTest do
  @moduledoc false
  use ExUnit.Case
  # alias Phoenix.PubSub
  alias ServerlogDaemon.FtpWorker

  import Mock

  doctest FtpWorker

  # setup_with_mocks([
  #   {PubSub, [], broadcast: fn _pub_sub, _server_id, _data -> :ok end}
  # ]) do
  #   :ok
  # end
    test "start_link" do
      assert {:ok, _pid} = FtpWorker.start_link(%{name: :wtf})
    end
end
