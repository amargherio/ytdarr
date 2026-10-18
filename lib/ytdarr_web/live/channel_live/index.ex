defmodule YtdarrWeb.ChannelLive.Index do
  use YtdarrWeb, :live_view

  alias Ytdarr.Content

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:channels}>
      <.header>
        Listing Channels
        <:actions>
          <.button variant="primary" navigate={~p"/channels/add"}>
            <.icon name="hero-plus" /> New Channel
          </.button>
        </:actions>
      </.header>

      <div class="flex flex-wrap items-center justify-between gap-3 border-y border-base-300 py-3">
        <div class="flex flex-wrap items-center gap-4">
          <.input
            id="select-all-channels"
            name="select_all_channels"
            type="checkbox"
            label="Select all"
            checked={MapSet.size(@channel_ids) > 0 and @selected_channel_ids == @channel_ids}
            disabled={MapSet.size(@channel_ids) == 0}
            phx-click="toggle-select-all"
            class="size-4 cursor-pointer rounded border border-base-300 bg-base-100 accent-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed"
          />
          <p id="channel-selection-count" class="text-sm text-base-content/70" aria-live="polite">
            {MapSet.size(@selected_channel_ids)} of {MapSet.size(@channel_ids)} selected
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <.button
            id="refresh-selected-channels"
            type="button"
            phx-click="refresh-selected"
            phx-disable-with="Queueing…"
            disabled={MapSet.size(@selected_channel_ids) == 0}
            class="inline-flex min-h-9 items-center gap-2 rounded-lg bg-primary/10 px-3 py-2 text-sm font-medium text-primary transition-colors hover:bg-primary/20 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-40 motion-reduce:transition-none"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Refresh selected
          </.button>
          <.button
            id="refresh-all-channels"
            type="button"
            phx-click="refresh-all"
            phx-disable-with="Queueing…"
            disabled={MapSet.size(@channel_ids) == 0}
            class="inline-flex min-h-9 items-center gap-2 rounded-lg border border-base-300 px-3 py-2 text-sm font-medium transition-colors hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-40 motion-reduce:transition-none"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Refresh all
          </.button>
        </div>
      </div>

      <.table id="channels" rows={@streams.channels}>
        <:col :let={{_id, channel}} label="Select">
          <.input
            id={"select-channel-#{channel.id}"}
            name={"select_channel_#{channel.id}"}
            type="checkbox"
            aria-label={"Select #{channel.name}"}
            checked={MapSet.member?(@selected_channel_ids, to_string(channel.id))}
            phx-click="toggle-channel-selection"
            phx-value-id={channel.id}
            class="size-4 cursor-pointer rounded border border-base-300 bg-base-100 accent-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          />
        </:col>
        <:col :let={{_id, channel}} label="Avatar">
          <img
            src={~p"/images/channels/#{channel.id}/avatar"}
            alt="Avatar"
            class="w-10 h-10 rounded-full"
          />
        </:col>
        <:col :let={{_id, channel}} label="Name">
          <.link
            navigate={~p"/channels/#{channel}"}
            class="font-medium hover:text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            {channel.name}
          </.link>
        </:col>
        <:col :let={{_id, channel}} label="Description">{channel.description}</:col>
        <:col :let={{_id, channel}} label="Channel Stats">
          <div>Monitored: {channel.is_monitored}</div>
          <div>Last Checked: {channel.last_checked_at}</div>
          <div>Platform: {channel.platform}</div>
          <div>Channel URL: <a href={channel.url}>{channel.platform_username}</a></div>
        </:col>
        <:action :let={{_id, channel}}>
          <div class="sr-only">
            <.link navigate={~p"/channels/#{channel}"}>Show</.link>
          </div>
          <.link navigate={~p"/channels/#{channel}/edit"}>Edit</.link>
        </:action>
        <:action :let={{_id, channel}}>
          <details class="relative">
            <summary
              id={"remove-channel-#{channel.id}"}
              class="btn btn-ghost btn-sm list-none gap-1 text-error hover:bg-error/10 [&::-webkit-details-marker]:hidden"
            >
              <.icon name="hero-trash" class="size-4" /> Remove
              <.icon name="hero-chevron-down" class="size-3" />
            </summary>
            <div class="absolute right-0 z-20 mt-1 w-64 rounded-lg border border-base-300 bg-base-100 p-2 shadow-lg">
              <p class="px-2 py-1 text-xs font-medium text-base-content/60">Downloaded files</p>
              <button
                id={"remove-channel-keep-files-#{channel.id}"}
                type="button"
                class="btn btn-ghost btn-sm w-full justify-start gap-2 font-normal"
                phx-click="delete"
                phx-value-id={channel.id}
                phx-value-files="keep"
                data-confirm={"Remove #{channel.name} from Ytdarr? Downloaded files will be kept."}
              >
                <.icon name="hero-archive-box" class="size-4" /> Keep downloaded files
              </button>
              <button
                id={"remove-channel-delete-files-#{channel.id}"}
                type="button"
                class="btn btn-ghost btn-sm w-full justify-start gap-2 font-normal text-error hover:bg-error/10"
                phx-click="delete"
                phx-value-id={channel.id}
                phx-value-files="delete"
                data-confirm={"Remove #{channel.name} and permanently delete its downloaded files? This cannot be undone."}
              >
                <.icon name="hero-trash" class="size-4" /> Delete downloaded files
              </button>
            </div>
          </details>
        </:action>

        <%!-- <:col :let={{_id, channel}} label="Name">{channel.name}</:col>
        <:col :let={{_id, channel}} label="External">{channel.external_id}</:col>
        <:col :let={{_id, channel}} label="Url">{channel.url}</:col>
        <:col :let={{_id, channel}} label="Description">{channel.description}</:col>
        <:col :let={{_id, channel}} label="Platform">{channel.platform}</:col>
        <:col :let={{_id, channel}} label="Avatar url">{channel.avatar_url}</:col>
        <:col :let={{_id, channel}} label="Is monitored">{channel.is_monitored}</:col>
        <:col :let={{_id, channel}} label="Is monitored since">{channel.is_monitored_since}</:col>
        <:col :let={{_id, channel}} label="Last checked at">{channel.last_checked_at}</:col>
        <:col :let={{_id, channel}} label="Base path">{channel.base_path}</:col>
        <:col :let={{_id, channel}} label="Generic video path">{channel.generic_video_path}</:col> --%>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    channels = Content.list_channels!()

    {:ok,
     socket
     |> assign(:page_title, "Listing Channels")
     |> assign(:selected_channel_ids, MapSet.new())
     |> put_channels(channels)}
  end

  @impl true
  def handle_event("toggle-channel-selection", %{"id" => id}, socket) do
    with true <- MapSet.member?(socket.assigns.channel_ids, id),
         {:ok, channel} <- Content.get_channel(id) do
      selected = socket.assigns.selected_channel_ids

      selected =
        if MapSet.member?(selected, id),
          do: MapSet.delete(selected, id),
          else: MapSet.put(selected, id)

      {:noreply,
       socket
       |> assign(:selected_channel_ids, selected)
       |> stream_insert(:channels, channel)}
    else
      _ -> {:noreply, put_channels(socket, Content.list_channels!())}
    end
  end

  def handle_event("toggle-select-all", _params, socket) do
    channels = Content.list_channels!()
    socket = put_channels(socket, channels)

    selected =
      if socket.assigns.selected_channel_ids == socket.assigns.channel_ids,
        do: MapSet.new(),
        else: socket.assigns.channel_ids

    {:noreply,
     socket
     |> assign(:selected_channel_ids, selected)
     |> stream(:channels, channels, reset: true)}
  end

  def handle_event("refresh-selected", _params, socket) do
    refresh_channels(socket, :selected)
  end

  def handle_event("refresh-all", _params, socket) do
    refresh_channels(socket, :all)
  end

  def handle_event("delete", %{"id" => id, "files" => "keep"}, socket) do
    remove_channel(socket, id, false)
  end

  def handle_event("delete", %{"id" => id, "files" => "delete"}, socket) do
    remove_channel(socket, id, true)
  end

  defp remove_channel(socket, id, delete_files?) do
    channel = Content.get_channel!(id)

    case Content.destroy_channel(channel, %{delete_files: delete_files?}) do
      :ok ->
        message =
          if delete_files?,
            do: "Channel and downloaded files removed.",
            else: "Channel removed. Downloaded files were kept."

        {:noreply,
         socket
         |> stream_delete(:channels, channel)
         |> assign(:channel_ids, MapSet.delete(socket.assigns.channel_ids, to_string(channel.id)))
         |> assign(
           :selected_channel_ids,
           MapSet.delete(socket.assigns.selected_channel_ids, to_string(channel.id))
         )
         |> put_flash(:info, message)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not remove channel.")}
    end
  end

  defp put_channels(socket, channels) do
    channel_ids = MapSet.new(channels, &to_string(&1.id))

    socket
    |> assign(:channel_ids, channel_ids)
    |> assign(
      :selected_channel_ids,
      MapSet.intersection(socket.assigns.selected_channel_ids, channel_ids)
    )
    |> stream(:channels, channels, reset: true)
  end

  defp refresh_channels(socket, scope) do
    channels = Content.list_channels!()

    targets =
      case scope do
        :all ->
          channels

        :selected ->
          Enum.filter(
            channels,
            &MapSet.member?(socket.assigns.selected_channel_ids, to_string(&1.id))
          )
      end

    {queued_count, failed_ids} =
      Enum.reduce(targets, {0, MapSet.new()}, fn channel, {queued_count, failed_ids} ->
        case Content.sync_content("channel", channel.id) do
          {:ok, _job} -> {queued_count + 1, failed_ids}
          {:error, _error} -> {queued_count, MapSet.put(failed_ids, to_string(channel.id))}
        end
      end)

    {:noreply,
     socket
     |> assign(:selected_channel_ids, failed_ids)
     |> put_channels(channels)
     |> put_refresh_flash(queued_count, MapSet.size(failed_ids))}
  end

  defp put_refresh_flash(socket, 0, 0) do
    put_flash(socket, :info, "No channels to refresh.")
  end

  defp put_refresh_flash(socket, queued_count, 0) do
    put_flash(socket, :info, "Channel refreshes queued: #{queued_count}.")
  end

  defp put_refresh_flash(socket, queued_count, failed_count) do
    put_flash(
      socket,
      :error,
      "Channel refreshes queued: #{queued_count}. Could not queue #{failed_count}; select Refresh selected to try again."
    )
  end
end
