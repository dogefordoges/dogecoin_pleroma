defmodule DogecoinPleroma do
  defmodule AccountStorage do
    use GenServer

    def start_link(_state) do
      {:ok, table} = :dets.open_file(:accounts, type: :set)
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
    def register_app(client_name, redirect_uris, scopes, website \\ nil) do
      {:ok, %{:body => body}} =
        post(
          "/api/v1/apps",
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
      {:ok, %{:body => body}} =
        post(
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

    def get_direct_statuses(token, id \\ nil) do
      url =
        if id do
          "/api/v1/timelines/direct?since_id=#{id}"
        else
          "/api/v1/timelines/direct"
        end

      {:ok, %{:body => body}} =
        HTTPoison.get(
          Application.get_env(:dogecoin_pleroma, :url) <> url,
          [{"Authorization", "Bearer #{token}"}]
        )

      Jason.decode!(body)
    end

    def send_direct_status(token, status, id \\ nil) do
      {:ok, %{:body => body}} =
        post(
          "/api/v1/statuses",
          %{
            "status" => status,
            "visibility" => "direct",
            "in_reply_to_id" => id
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

    def start_link(_state) do
      GenServer.start_link(__MODULE__, %{})
    end

    @impl true
    def init(state) do
      # Schedule work to be performed on start
      schedule_work()
      {:ok, state}
    end

    def process_status(status) do
      %{
        "id" => id,
        "account" => %{
          "url" => url
        },
        "content" => content
      } = status

      {id, process_url(url), process_content(content)}
    end

    def process_content(content) do
      s = String.split(content, "</span>")
      Enum.at(s, -1) |> String.trim()
    end

    def process_url(url) do
      s = String.split(url)
      # { domain, username }
      {Enum.at(s, 2), Enum.at(s, 4)}
    end

    def execute_response(credentials, {id, {domain, username}, content}) do
      access_token = Map.get(credentials, "access_token")

      tokens = String.split(content, " ")
      command = Enum.first(tokens)

      case command do
        "register" -> register_response(access_token, id, domain, username, tokens)
        "search" -> search_response(access_token, id, domain, username, tokens)
        _ -> default_response(access_token, domain, username, id)
      end
    end

    def register_response(access_token, id, domain, username, tokens) do
      address = Enum.at(tokens, 1)
      url = "#{username}@#{domain}"

      if DogecoinPleroma.valid_address?(address) do
        AccountStorage.insert(url, address)

        Pleroma.send_direct_message(
          access_token,
          "@#{url} registered #{address} to #{url} much wow!",
          id
        )
      else
        Pleroma.send_direct_message(
          access_token,
          "@#{url} #{address} is not a valid :doge: address!",
          id
        )
      end
    end

    def search_response(access_token, id, domain, username, tokens) do
      url = "#{username}@#{domain}"

      case AccountStorage.lookup(url) do
        :error -> Pleroma.send_direct_status(access_token, "@#{url} is not registered!", id)
        address -> Pleroma.send_direct_status(access_token, "@#{url} address", id)
      end
    end

    def default_response(access_token, domain, username, id) do
      url = "#{username}@#{domain}"
      Pleroma.send_direct_status(access_token, "@#{url} i don't understand... many sads", id)
    end

    @impl true
    def handle_info(:work, state) do
      credentials = Pleroma.log_in()

      statuses =
        credentials
        |> Map.get("access_token")
        |> Pleroma.get_direct_statuses(Map.get(state, :id))
        |> Enum.map(&process_status/1)

      {id, _domain_username, _content} = Enum.first(statuses)

      Enum.each(statuses, fn status ->
        Task.async(fn -> execute_response(credentials, status) end)
      end)

      # Do the desired work here
      # Reschedule once more
      schedule_work()
      {:noreply, Map.put(state, :id, id)}
    end

    defp schedule_work() do
      # In 30 seconds
      Process.send_after(self(), :work, 30_000)
    end
  end
end
