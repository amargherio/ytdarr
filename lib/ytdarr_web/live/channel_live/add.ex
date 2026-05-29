defmodule YtdarrWeb.ChannelLive.Add do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Add Channel")
     |> assign(:add_method, :search)
     |> assign(:search, "")
     |> assign(:results, [])
     |> assign(:loading?, false)
     |> assign(:mode, :channels)
     |> assign(:channels_lookup, preload_channels_map())
     |> assign(:monitored_channel_ids, monitored_channel_ids())
     |> assign(:monitored_playlist_ids, monitored_playlist_ids())
     |> assign(:adding_ids, MapSet.new())
     |> assign(:search_ref, nil)
     |> assign(:direct_input, "")
     |> assign(:resolved_channel, nil)
     |> assign(:resolving?, false)
     |> assign(:resolve_ref, nil)
     |> assign(:resolve_error, nil)
     |> assign(:already_tracked_channel, nil)}
  end

  @impl true
  def handle_event("set-add-method", %{"method" => method}, socket)
      when method in ["search", "direct"] do
    {:noreply,
     socket
     |> assign(:add_method, String.to_existing_atom(method))
     |> assign(:resolved_channel, nil)
     |> assign(:resolve_error, nil)
     |> assign(:resolving?, false)
     |> assign(:already_tracked_channel, nil)
     |> assign(:results, [])
     |> assign(:search, "")
     |> assign(:direct_input, "")}
  end

  def handle_event("set-mode", %{"mode" => mode}, socket) when mode in ["channels"] do
    mode_atom = String.to_existing_atom(mode)

    {:noreply,
     socket
     |> assign(:mode, mode_atom)
     |> assign(:search, "")
     |> assign(:results, [])
     |> assign(:end_of_results?, false)}
  end

  def handle_event("resolve", %{"identifier" => identifier}, socket) do
    ref = make_ref()
    lv = self()

    Task.start(fn ->
      result = Content.resolve_channel(identifier)
      send(lv, {:async_resolve_result, ref, result})
    end)

    {:noreply,
     socket
     |> assign(:direct_input, identifier)
     |> assign(:resolve_ref, ref)
     |> assign(:resolving?, identifier != "")
     |> assign(:resolved_channel, nil)
     |> assign(:resolve_error, nil)}
  end

  def handle_event(
        "direct-add",
        %{"external_id" => external_id} = params,
        socket
      ) do
    should_sync = Map.get(params, "sync", "false") == "true"
    should_monitor = Map.get(params, "monitor", "false") == "true"
    resolved = socket.assigns.resolved_channel

    cond do
      MapSet.member?(socket.assigns.monitored_channel_ids, external_id) ->
        {:noreply, put_flash(socket, :info, "Channel already monitored")}

      match?({:ok, %Content.Channel{}}, Content.get_channel_by_external_id(external_id)) ->
        {:ok, existing} = Content.get_channel_by_external_id(external_id)

        {:noreply,
         socket
         |> update(:monitored_channel_ids, &MapSet.put(&1, external_id))
         |> assign(:already_tracked_channel, existing)
         |> put_flash(:info, "Channel is already tracked.")}

      resolved && resolved.external_id == external_id ->
        attrs = %{
          name: resolved.name,
          external_id: resolved.external_id,
          url: resolved.url,
          avatar_url: resolved.avatar_url,
          description: resolved.description,
          platform: "YouTube",
          platform_username: resolved.platform_username,
          uploads_playlist_id: resolved.uploads_playlist_id
        }

        socket = update(socket, :adding_ids, &MapSet.put(&1, external_id))

        case Content.create_channel(attrs) do
          {:ok, channel} ->
            if should_monitor do
              Content.monitor_channel(channel)
            end

            if !should_monitor && should_sync do
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
        {:noreply, put_flash(socket, :error, "No resolved channel to add")}
    end
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

  def handle_info(
        {:async_resolve_result, ref, result},
        %{assigns: %{resolve_ref: ref}} = socket
      ) do
    socket =
      case result do
        {:ok, channel} ->
          socket
          |> assign(:resolved_channel, channel)
          |> assign(:resolving?, false)
          |> assign(:resolve_error, nil)

        {:already_tracked, channel} ->
          socket
          |> assign(:resolved_channel, nil)
          |> assign(:resolving?, false)
          |> assign(:resolve_error, nil)
          |> assign(:already_tracked_channel, channel)
          |> put_flash(:info, "Channel \"#{channel.name}\" is already tracked.")

        {:error, :not_found} ->
          socket
          |> assign(:resolved_channel, nil)
          |> assign(:resolving?, false)
          |> assign(
            :resolve_error,
            "Channel not found. Check the handle, URL, or ID and try again."
          )

        {:error, :empty_input} ->
          socket
          |> assign(:resolved_channel, nil)
          |> assign(:resolving?, false)
          |> assign(:resolve_error, "Please enter a YouTube handle, channel URL, or channel ID.")

        {:error, :unrecognized} ->
          socket
          |> assign(:resolved_channel, nil)
          |> assign(:resolving?, false)
          |> assign(
            :resolve_error,
            "Unrecognized format. Try a @handle, channel URL, or channel ID starting with UC."
          )

        {:error, _reason} ->
          socket
          |> assign(:resolved_channel, nil)
          |> assign(:resolving?, false)
          |> assign(:resolve_error, "Failed to look up channel. Please try again.")
      end

    {:noreply, socket}
  end

  def handle_info({:async_resolve_result, _old_ref, _result}, socket) do
    # stale resolve result ignored
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:channel_add}>
      <.header>
        Add Channel
        <:subtitle>Search YouTube or add a channel directly by handle, URL, or ID.</:subtitle>
        <:actions>
          <.button navigate={~p"/channels"}>Back</.button>
        </:actions>
      </.header>

      <div class="space-y-6">
        <%!-- Add method tabs --%>
        <div id="add-method-tabs" class="flex gap-1 border-b border-base-300 pb-0">
          <button
            type="button"
            phx-click="set-add-method"
            phx-value-method="search"
            class={[
              "px-4 py-2 text-sm font-medium rounded-t-lg transition-colors",
              if(@add_method == :search,
                do: "bg-base-100 border border-b-0 border-base-300 -mb-px text-primary",
                else: "text-base-content/60 hover:text-base-content/80"
              )
            ]}
          >
            <.icon name="hero-magnifying-glass" class="w-4 h-4 mr-1" /> Search
          </button>
          <button
            type="button"
            phx-click="set-add-method"
            phx-value-method="direct"
            class={[
              "px-4 py-2 text-sm font-medium rounded-t-lg transition-colors",
              if(@add_method == :direct,
                do: "bg-base-100 border border-b-0 border-base-300 -mb-px text-primary",
                else: "text-base-content/60 hover:text-base-content/80"
              )
            ]}
          >
            <.icon name="hero-link" class="w-4 h-4 mr-1" /> Direct Add
          </button>
        </div>

        <%!-- Search tab content --%>
        <div :if={@add_method == :search} id="search-tab">
          <div class="flex gap-2 mb-4">
            <button
              type="button"
              phx-click="set-mode"
              phx-value-mode="channels"
              class={["btn btn-sm", @mode == :channels && "btn-primary"]}
            >
              Channels
            </button>
          </div>
          <form phx-submit="search" class="flex flex-col gap-2" autocomplete="off" id="search-form">
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

          <div :if={@loading?} class="flex items-center gap-2 text-sm mt-4">
            <span class="loading loading-spinner loading-sm" /> Searching...
          </div>

          <div
            :if={@results == [] and @search != "" and !@loading?}
            class="text-sm opacity-70 mt-4"
          >
            No results.
          </div>

          <div :if={@results != [] and @mode == :channels} class="overflow-x-auto mt-4">
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
                        not r.is_monitored and
                          not MapSet.member?(@monitored_channel_ids, r.external_id)
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
                        {(MapSet.member?(@adding_ids, r.external_id) && "Adding...") ||
                          "Add & Sync"}
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

          <div :if={@results != [] and @mode == :playlists} class="overflow-x-auto mt-4">
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

        <%!-- Direct Add tab content --%>
        <div :if={@add_method == :direct} id="direct-add-tab">
          <form
            phx-submit="resolve"
            class="flex flex-col gap-2"
            autocomplete="off"
            id="resolve-form"
          >
            <div class="flex gap-2">
              <input
                type="text"
                name="identifier"
                value={@direct_input}
                placeholder="@handle, channel URL, or channel ID (UCxxxx)"
                class="input input-bordered flex-1"
                id="direct-input"
              />
              <.button type="submit" phx-disable-with="Looking up...">
                <.icon name="hero-arrow-path" class="w-5 h-5" /> Look Up
              </.button>
            </div>
            <p class="text-xs opacity-60">
              Enter a YouTube handle (e.g. @dirty-civilian), channel URL, or channel ID.
              Uses 1 API quota unit instead of 100 for search.
            </p>
          </form>

          <div :if={@resolving?} class="flex items-center gap-2 text-sm mt-4">
            <span class="loading loading-spinner loading-sm" /> Looking up channel...
          </div>

          <div :if={@resolve_error} class="alert alert-error mt-4" id="resolve-error">
            <.icon name="hero-exclamation-circle" class="w-5 h-5" />
            <span>{@resolve_error}</span>
          </div>

          <%!-- Already tracked channel link --%>
          <div
            :if={@already_tracked_channel && !@resolving? && !@resolved_channel}
            class="alert alert-info mt-4"
            id="already-tracked-notice"
          >
            <.icon name="hero-information-circle" class="w-5 h-5" />
            <span>This channel is already tracked.</span>
            <.link
              navigate={~p"/channels/#{@already_tracked_channel}"}
              class="btn btn-sm btn-ghost"
            >
              View channel →
            </.link>
          </div>

          <%!-- Preview card --%>
          <div
            :if={@resolved_channel && !@resolving?}
            class="card bg-base-200 shadow-md mt-4"
            id="channel-preview"
          >
            <div class="card-body">
              <div class="flex items-start gap-4">
                <img
                  :if={@resolved_channel.avatar_url}
                  src={@resolved_channel.avatar_url}
                  class="w-16 h-16 rounded-full shrink-0"
                />
                <div class="flex-1 min-w-0">
                  <h3 class="card-title text-lg">{@resolved_channel.name}</h3>
                  <p :if={@resolved_channel.platform_username} class="text-sm opacity-70">
                    <code>{@resolved_channel.platform_username}</code>
                  </p>
                  <p :if={@resolved_channel.description} class="text-sm mt-2 line-clamp-3">
                    {@resolved_channel.description}
                  </p>
                  <p class="text-xs opacity-50 mt-1">
                    <.link
                      href={@resolved_channel.url}
                      target="_blank"
                      class="hover:underline"
                    >
                      {@resolved_channel.url}
                      <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3 inline" />
                    </.link>
                  </p>
                </div>
              </div>

              <div class="card-actions justify-end mt-4">
                <.button
                  phx-click="direct-add"
                  phx-value-external_id={@resolved_channel.external_id}
                  phx-value-sync="true"
                  phx-value-monitor="false"
                  disabled={MapSet.member?(@adding_ids, @resolved_channel.external_id)}
                  id="direct-add-sync"
                >
                  <span
                    :if={MapSet.member?(@adding_ids, @resolved_channel.external_id)}
                    class="loading loading-spinner loading-xs mr-1"
                  /> Add & Sync
                </.button>

                <.button
                  phx-click="direct-add"
                  phx-value-external_id={@resolved_channel.external_id}
                  phx-value-sync="true"
                  phx-value-monitor="true"
                  disabled={MapSet.member?(@adding_ids, @resolved_channel.external_id)}
                  id="direct-add-monitor-sync"
                >
                  Add, Monitor, & Sync
                </.button>

                <.button
                  phx-click="direct-add"
                  phx-value-external_id={@resolved_channel.external_id}
                  phx-value-sync="false"
                  phx-value-monitor="false"
                  disabled={MapSet.member?(@adding_ids, @resolved_channel.external_id)}
                  id="direct-add-only"
                >
                  Add Only
                </.button>
              </div>
            </div>
          </div>
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
