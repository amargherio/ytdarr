defmodule YtdarrWeb.ChannelLive.Add do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content
  alias Ytdarr.Repo

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Add Channel")
     |> assign(:search, "")
     |> assign(:results, [])
     |> assign(:loading?, false)
     |> assign(:mode, :channels)
     |> assign(:channels_lookup, preload_channels_map())
     |> assign(:monitored_channel_ids, monitored_channel_ids())
     |> assign(:monitored_playlist_ids, monitored_playlist_ids())
     |> assign(:adding_ids, MapSet.new())
     |> assign(:search_ref, nil)}
  end

  @impl true
  def handle_event("set-mode", %{"mode" => mode}, socket) when mode in ["channels"] do
    mode_atom = String.to_existing_atom(mode)

    {:noreply,
     socket
     |> assign(:mode, mode_atom)
     |> assign(:search, "")
     |> assign(:results, [])
     |> assign(:end_of_results?, false)}
  end

  def handle_event("search", %{"q" => q}, socket) do
    # Cancel previous pending by ignoring its message when ref doesn't match
    ref = make_ref()
    mode = socket.assigns.mode
    chan_map = socket.assigns.channels_lookup

    Task.start(fn ->
      results = mock_channel_search(q)
      send(self(), {:async_search_result, ref, q, results})
    end)

    {:noreply,
     socket
     |> assign(:search, q)
     |> assign(:search_ref, ref)
     |> assign(:loading?, q != "")}
  end

  def handle_event("queue-search", %{"q" => q}, socket) do
    # For future async handling (Task + handle_info) if needed
    {:noreply, assign(socket, search: q, loading?: true)}
  end

  def handle_event(
        "add",
        %{"external_id" => external_id, "name" => name, "url" => url},
        %{assigns: %{mode: :channels}} = socket
      ) do
    attrs = %{
      name: name,
      external_id: external_id,
      url: url,
      platform: "YouTube"
    }

    id = external_id

    cond do
      # Revisit the MapSet use here
      MapSet.member?(socket.assigns.monitored_channel_ids, external_id) ->
        {:noreply, put_flash(socket, :info, "Channel already monitored")}

      Content.get_channel_by_external_id(external_id) ->
        {:noreply,
         socket
         |> update(:monitored_channel_ids, &MapSet.put(&1, external_id))
         |> put_flash(:info, "Channel already existed and is now marked as monitored")}

      true ->
        socket = update(socket, :adding_ids, &MapSet.put(&1, id))

        case Content.create_channel(attrs) do
          {:ok, channel} ->
            {:noreply,
             socket
             |> update(:monitored_channel_ids, &MapSet.put(&1, channel.external_id))
             |> update(:adding_ids, &MapSet.delete(&1, id))
             |> put_flash(:info, "Channel added")
             |> push_navigate(to: ~p"/channels/#{channel}")}

          {:error, changeset} ->
            {:noreply,
             socket
             |> update(:adding_ids, &MapSet.delete(&1, id))
             |> put_flash(:error, friendly_errors(changeset))}
        end
    end
  end

  @impl true
  def handle_info(
        {:async_search_result, ref, q, results},
        %{assigns: %{search_ref: ref}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:results, results)
     |> assign(:loading?, false)
     |> assign(:search, q)}
  end

  def handle_info({:async_search_result, _old_ref, _q, _results}, socket) do
    # stale result ignored
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:content_add}>
      <.header>
        Add Channel
        <:subtitle>Search YouTube (mock) and add channels to monitor.</:subtitle>
        <:actions>
          <.button navigate={~p"/channels"}>Back</.button>
        </:actions>
      </.header>

      <div class="space-y-6">
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="set-mode"
            phx-value-mode="channels"
            class={["btn btn-sm", @mode == :channels && "btn-primary"]}
          >
            Channels
          </button>
        </div>
        <form phx-keyup="search" phx-submit="noop" class="flex flex-col gap-2" autocomplete="off">
          <input
            type="text"
            name="q"
            value={@search}
            placeholder={
              (@mode == :channels && "Search YouTube channels...") || "Search YouTube playlists..."
            }
            class="input input-bordered"
            phx-debounce="300"
          />
          <p class="text-xs opacity-60">Type to search {@mode}. (Mocked data for now.)</p>
        </form>

        <div :if={@loading?} class="flex items-center gap-2 text-sm">
          <span class="loading loading-spinner loading-sm" /> Searching...
        </div>

        <div :if={@results == [] and @search != "" and !@loading?} class="text-sm opacity-70">
          No results.
        </div>

        <div :if={@results != [] and @mode == :channels} class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Avatar</th>
                <th>Name</th>
                <th>External ID</th>
                <th>Subscribers</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @results}>
                <td>
                  <img :if={r.avatar_url} src={r.avatar_url} class="w-10 h-10 rounded-full" />
                </td>
                <td>{r.name}</td>
                <td><code>{r.external_id}</code></td>
                <td>{r.subscriber_count}</td>
                <td>
                  <span
                    :if={MapSet.member?(@monitored_channel_ids, r.external_id)}
                    class="badge badge-success"
                  >
                    Monitored
                  </span>
                  <.button
                    :if={!MapSet.member?(@monitored_channel_ids, r.external_id)}
                    phx-click="add"
                    phx-value-external_id={r.external_id}
                    phx-value-name={r.name}
                    phx-value-url={r.url}
                    variant="primary"
                    class="btn-xs"
                    disabled={MapSet.member?(@adding_ids, r.external_id)}
                  >
                    <span
                      :if={MapSet.member?(@adding_ids, r.external_id)}
                      class="loading loading-spinner loading-xs mr-1"
                    />
                    {(MapSet.member?(@adding_ids, r.external_id) && "Adding...") || "Add"}
                  </.button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@results != [] and @mode == :playlists} class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>Name</th>
                <th>External ID</th>
                <th>Videos</th>
                <th>Channel</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @results}>
                <td>{r.name}</td>
                <td><code>{r.external_id}</code></td>
                <td>{r.video_count}</td>
                <td>{Map.get(@channels_lookup, r.channel_id).name}</td>
                <td>
                  <span
                    :if={MapSet.member?(@monitored_playlist_ids, r.external_id)}
                    class="badge badge-success"
                  >
                    Monitored
                  </span>
                  <.button
                    :if={!MapSet.member?(@monitored_playlist_ids, r.external_id)}
                    phx-click="add"
                    phx-value-external_id={r.external_id}
                    phx-value-name={r.name}
                    phx-value-url={r.url}
                    phx-value-channel_id={r.channel_id}
                    variant="primary"
                    class="btn-xs"
                    disabled={MapSet.member?(@adding_ids, r.external_id)}
                  >
                    <span
                      :if={MapSet.member?(@adding_ids, r.external_id)}
                      class="loading loading-spinner loading-xs mr-1"
                    />
                    {(MapSet.member?(@adding_ids, r.external_id) && "Adding...") || "Add"}
                  </.button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Mock search helpers (to be replaced with real API integration)
  defp mock_channel_search(""), do: []
  defp mock_channel_search(nil), do: []

  defp mock_channel_search(query) do
    base = String.replace(query, ~r/\s+/, "-") |> String.downcase()

    for i <- 1..min(5, String.length(query)) do
      %{
        name: "#{String.capitalize(query)} Channel #{i}",
        external_id: "mock-chan-#{base}-#{i}",
        url: "https://www.youtube.com/@#{base}#{i}",
        avatar_url: "https://via.placeholder.com/64?text=#{URI.encode(query)}",
        subscriber_count: Enum.random(1_000..100_000) |> :erlang.integer_to_binary()
      }
    end
  end

  defp mock_playlist_search("", _map), do: []
  defp mock_playlist_search(nil, _map), do: []
  defp mock_playlist_search(_query, channels_map) when map_size(channels_map) == 0, do: []

  defp mock_playlist_search(query, channels_map) do
    channel_ids = Map.keys(channels_map)
    base = String.replace(query, ~r/\s+/, "-") |> String.downcase()

    for i <- 1..min(5, String.length(query)) do
      ch_id = Enum.at(channel_ids, rem(i, length(channel_ids)))

      %{
        name: "#{String.capitalize(query)} Playlist #{i}",
        external_id: "mock-pl-#{base}-#{i}",
        url: "https://www.youtube.com/playlist?list=#{base}#{i}",
        video_count: Enum.random(5..200),
        channel_id: ch_id,
        implicitly_monitored?:
          MapSet.member?(monitored_channel_ids(), Map.get(channels_map, ch_id).external_id)
      }
    end
  end

  defp preload_channels_map do
    Content.list_monitored_channels()
    |> Repo.preload([])
    |> Map.new(fn ch -> {ch.id, ch} end)
  end

  defp monitored_channel_ids do
    Content.list_monitored_channels() |> Enum.map(& &1.external_id) |> MapSet.new()
  end

  defp monitored_playlist_ids do
    Content.list_playlists_for_channel() |> Enum.map(& &1.external_id) |> MapSet.new()
  end

  defp channel_monitored_and_includes_playlist?(channel_id, _playlist_external_id) do
    case Content.get_channel!(channel_id) do
      %{is_monitored: true} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp friendly_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {f, {m, _}} -> "#{Phoenix.Naming.humanize(f)} #{m}" end)
    |> Enum.join(", ")
  end
end
