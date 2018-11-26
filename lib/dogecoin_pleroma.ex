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

  def valid_address?(address) do
    {:ok, %{"isvalid" => validity}} = Dogex.validate_address(address)
    validity
  end
  
  defmodule Pleroma do

    def register_app(url, client_name, redirect_uris, scopes, website) do
      {:ok, %{:body => body}} = post(
	url,
	%{
	  "client_name" => client_name,
	  "redirect_uris" => redirect_uris,
	  "scopes" => scopes,
	  "website" => website
	}
      )
      Jason.decode!(body)
    end

    def log_in() do
      {:ok, %{:body => body}} = post(
	"/oauth/token",
	%{
	  "client_id" => Application.get_env(:dogecoin_pleroma, :client_id),
	  "client_secret" => Application.get_env(:dogecoin_pleroma, :client_secret),
	  "grant_type" => "password",
	  "username" => Application.get_env(:dogecoin_pleroma, :username),
	  "password" => Application.get_env(:dogecoin_pleroma, :password)
	  }
      )
      Jason.decode!(body)
    end

    def get_direct_statuses(token) do
      {:ok, %{:body => body}} = HTTPoison.get(
	Application.get_env(:dogecoin_pleroma, :url) <> "/api/v1/timelines/direct",
	[{"Authorization", "Bearer #{token}"}]
      )
      Jason.decode!(body)
    end

    def send_direct_status(token, status) do
      {:ok, %{:body => body}} = post(
	"/api/v1/statuses",
	%{
	  "status" => status,
	  "visibility" => "direct"	  
	},
	[{"Authorization", "Bearer #{token}"}]
      )
      Jason.decode!(body)
    end
    
    def post(url, data, headers \\ []) do
      HTTPoison.post(
	Application.get_env(:dogecoin_pleroma, :url) <> url,
	Jason.encode!(data),
	[{"Content-Type", "application/json"}] ++ headers,
	[]
	)
    end
  end

  defmodule Bot do
    use GenServer

    def start_link do
      GenServer.start_link(__MODULE__, %{})
    end

    @impl true
    def init(state) do
      schedule_work() # Schedule work to be performed on start
      {:ok, state}
    end

    @impl true
    def handle_info(:work, state) do
      # Do the desired work here
      schedule_work() # Reschedule once more
      {:noreply, state}
    end

    defp schedule_work() do
      Process.send_after(self(), :work, 30_000) # In 30 seconds
    end
  end  
end
