defmodule DogecoinPleroma do

  defmodule AccountStorage do
    use GenServer

    def start_link(_state) do
      {:ok, table} = :dets.open_file(:accounts, [type: :set])
      GenServer.start_link(__MODULE__, %{:table => table}, name: Accounts)
    end

    def insert(key, value) do
      GenServer.call(Accounts, {:insert, {key, value}})
    end

    def lookup(key) do
      GenServer.call(Accounts, {:lookup, key})
    end

    def init(state) do
      {:ok, state}
    end  

    def handle_call({:insert, kv_tuple}, _from, %{:table => table} = state) do
      :dets.insert(table, kv_tuple)
      {:reply, :ok, state}
    end

    def handle_call({:lookup, key}, _from, %{:table => table} = state) do
      case :dets.lookup(table, key) do
	[{_key, value}] -> {:reply, value, state}
	[] -> {:reply, :error, state}
      end           
    end
  end
end
