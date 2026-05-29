defmodule YtdarrWeb.ChannelLive.Add do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  require Ash.Query

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
    lv = self()

    Task.start(fn ->
      results = perform_channel_search(q)
      send(lv, {:async_search_result, ref, q, results})
    end)

    {:noreply,
     socket
     |> assign(:search, q)
     |> assign(:search_ref, ref)
     |> assign(:loading?, q != "")}
  end

  def handle_event(
        "add",
        %{"external_id" => external_id} = params,
        %{assigns: %{mode: :channels}} = socket
      ) do
    should_sync = Map.get(params, "sync", "true") == "true"
    should_monitor = Map.get(params, "monitor", "true") == "true"
    selected_channel = Enum.find(socket.assigns.results, &(&1.external_id == external_id))

    cond do
      # Revisit the MapSet use here
      MapSet.member?(socket.assigns.monitored_channel_ids, external_id) ->
        {:noreply, put_flash(socket, :info, "Channel already monitored")}

      match?({:ok, %Content.Channel{}}, Content.get_channel_by_external_id(external_id)) ->
        {:noreply,
         socket
         |> update(:monitored_channel_ids, &MapSet.put(&1, external_id))
         |> put_flash(:info, "Channel already existed and is now marked as monitored")}

      selected_channel ->
        attrs = %{
          name: selected_channel.name,
          external_id: selected_channel.external_id,
          url: selected_channel.url,
          avatar_url: selected_channel.avatar_url,
          description: selected_channel.description,
          platform: "YouTube"
        }

        socket = update(socket, :adding_ids, &MapSet.put(&1, external_id))

        case Content.create_channel(attrs) do
          {:ok, channel} ->
            if should_monitor do
              Content.toggle_channel_monitor(channel.id)
            end

            if !should_monitor && should_sync do
              # For channels that are added without monitoring but with sync, we still want to trigger an initial sync to populate videos. We can do this asynchronously without blocking the response.
              Task.start(fn -> Content.sync_channel_content(channel.external_id) end)
            end

            {:noreply,
             socket
             |> update(:monitored_channel_ids, &MapSet.put(&1, channel.external_id))
             |> update(:adding_ids, &MapSet.delete(&1, external_id))
             |> put_flash(:info, "Channel added")
             |> push_navigate(to: ~p"/channels/#{channel}")}

          {:error, error} ->
            {:noreply,
             socket
             |> update(:adding_ids, &MapSet.delete(&1, external_id))
             |> put_flash(:error, friendly_errors(error))}
        end

      true ->
        {:noreply, put_flash(socket, :error, "Channel not found in results")}
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
    <Layouts.app flash={@flash} nav={:channel_add}>
      <.header>
        Add Channel
        <:subtitle>Search YouTube and add channels to monitor.</:subtitle>
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
        <form phx-submit="search" class="flex flex-col gap-2" autocomplete="off">
          <div class="flex gap-2">
            <input
              type="text"
              name="q"
              value={@search}
              placeholder={
                (@mode == :channels && "Search YouTube channels...") ||
                  "Search YouTube playlists..."
              }
              class="input input-bordered flex-1"
            />
            <.button type="submit" phx-disable-with="Searching...">
              <.icon name="hero-magnifying-glass" class="w-5 h-5" /> Search
            </.button>
          </div>
          <p class="text-xs opacity-60">Press Enter or click Search to find {@mode}.</p>
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
                <th></th>
                <th>Name</th>
                <th>Channel Alias</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @results}>
                <td>
                  <img :if={r.avatar_url} src={r.avatar_url} class="w-10 h-10 rounded-full" />
                </td>
                <td>{r.name}</td>
                <td><code>{r.platform_username}</code></td>
                <td>
                  <span
                    :if={r.is_monitored or MapSet.member?(@monitored_channel_ids, r.external_id)}
                    class="badge badge-success"
                  >
                    Monitored
                  </span>
                  <div
                    :if={
                      not r.is_monitored and not MapSet.member?(@monitored_channel_ids, r.external_id)
                    }
                    class="join"
                  >
                    <.button
                      phx-click="add"
                      phx-value-external_id={r.external_id}
                      phx-value-sync="true"
                      disabled={MapSet.member?(@adding_ids, r.external_id)}
                    >
                      <span
                        :if={MapSet.member?(@adding_ids, r.external_id)}
                        class="loading loading-spinner loading-xs mr-1"
                      />
                      {(MapSet.member?(@adding_ids, r.external_id) && "Adding...") || "Add & Sync"}
                    </.button>

                    <.button
                      phx-click="add"
                      phx-value-external_id={r.external_id}
                      phx-value-sync="true"
                      phx-value-monitor="true"
                      disabled={MapSet.member?(@adding_ids, r.external_id)}
                    >
                      Add, Monitor, & Sync
                    </.button>

                    <.button
                      phx-click="add"
                      phx-value-external_id={r.external_id}
                      phx-value-sync="false"
                      disabled={MapSet.member?(@adding_ids, r.external_id)}
                    >
                      Add Only
                    </.button>
                  </div>
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
                <th>Channel Alias</th>
                <th>Videos</th>
                <th>Channel</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={r <- @results}>
                <td>{r.name}</td>
                <td><code>{r.platform_username}</code></td>
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

  defp perform_channel_search(""), do: []
  defp perform_channel_search(nil), do: []

  defp perform_channel_search(query) do
    case Content.search_for_channels(query) do
      {:ok, channels} ->
        channels

      _ ->
        []
    end
  end

  defp preload_channels_map do
    Content.list_channels!(query: [filter: [is_monitored: true]])
    |> Map.new(fn ch -> {ch.id, ch} end)
  end

  defp monitored_channel_ids do
    Content.list_channels!(query: [filter: [is_monitored: true]])
    |> Enum.map(& &1.external_id)
    |> MapSet.new()
  end

  defp monitored_playlist_ids do
    Content.list_playlists!() |> Enum.map(& &1.external_id) |> MapSet.new()
  end

  defp friendly_errors(%Ash.Error.Invalid{} = error) do
    error.errors
    |> Enum.map(fn err -> err.message || "Validation error" end)
    |> Enum.join(", ")
  end

  defp friendly_errors(error) when is_binary(error), do: error
  defp friendly_errors(_error), do: "An error occurred"
end
