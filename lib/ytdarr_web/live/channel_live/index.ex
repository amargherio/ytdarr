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

      <ul class="menu bg-base-200 rounded-box w-56">
        <li><a>Overview</a></li>
        <li><a>Card</a></li>
        <li><a>Table</a></li>
      </ul>

      <.table
        id="channels"
        rows={@streams.channels}
        row_click={fn {_id, channel} -> JS.navigate(~p"/channels/#{channel}") end}
      >
        <:col :let={{_id, channel}} label="Avatar">
          <img
            src={~p"/images/channels/#{channel.id}/avatar"}
            alt="Avatar"
            class="w-10 h-10 rounded-full"
          />
        </:col>
        <:col :let={{_id, channel}} label="Name">{channel.name}</:col>
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
    {:ok,
     socket
     |> assign(:page_title, "Listing Channels")
     |> stream(:channels, Content.list_channels!())}
  end

  @impl true
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
         |> put_flash(:info, message)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Could not remove channel.")}
    end
  end
end
