defmodule YtdarrWeb.CustomComponents do
  use Phoenix.Component
  use Gettext, backend: YtdarrWeb.Gettext

  import YtdarrWeb.CoreComponents, only: [icon: 1]
  alias YtdarrWeb.ChannelLive.ImportModal

  @doc "Returns true when a video has a known upload date."
  @spec dated?(map()) :: boolean()
  def dated?(%{upload_date: upload_date}), do: not is_nil(upload_date)

  @doc "Returns the persisted import recovery entries for a video, defaulting to none."
  @spec recovery_entries(map()) :: [map()]
  def recovery_entries(video) do
    case Map.get(video, :import_recovery) do
      %{"entries" => entries} when is_list(entries) -> entries
      _ -> []
    end
  end

  @doc "Returns true when a video has no pending import recovery entries."
  @spec recovery_empty?(map()) :: boolean()
  def recovery_empty?(video), do: recovery_entries(video) == []

  @doc "Returns true when a video's download state alone (ignoring its date) permits importing."
  @spec import_state_ready?(map()) :: boolean()
  def import_state_ready?(video) do
    video.download_state in [:available, :missing] or
      (video.download_state == :import_failed and recovery_empty?(video))
  end

  @doc "Returns true when Import should be offered for a video, regardless of blocklist."
  @spec import_eligible?(map()) :: boolean()
  def import_eligible?(video), do: dated?(video) and import_state_ready?(video)

  @doc "Returns true when Import is state-eligible but disabled for lack of an upload date."
  @spec import_unavailable?(map()) :: boolean()
  def import_unavailable?(video), do: not dated?(video) and import_state_ready?(video)

  @doc "Returns true when Download should be offered for a video."
  @spec download_eligible?(map()) :: boolean()
  def download_eligible?(video), do: not video.is_blocklisted and import_state_ready?(video)

  @doc "Returns true when a Retry source recovery/cleanup control should be offered."
  @spec retry_recovery_eligible?(map()) :: boolean()
  def retry_recovery_eligible?(video) do
    video.download_state in [:import_failed, :downloaded] and not recovery_empty?(video)
  end

  @doc "Builds tooltip text for a pending-recovery indicator: a label plus each recovery path."
  @spec recovery_tooltip(String.t(), map()) :: String.t()
  def recovery_tooltip(label, video) do
    paths = video |> recovery_entries() |> Enum.map(& &1["path"])
    Enum.join([label | paths], "\n")
  end

  attr :variant, :string,
    values: ~w(primary secondary info success warning error),
    default: "primary"

  attr :size, :string, values: ~w(sm md lg), default: "md"
  attr :rest, :global, include: ~w(href navigate patch disabled)
  slot :inner_block, required: true

  def data_pill(assigns) do
    variants = %{
      "primary" => [
        "btn-primary",
        "text-primary-content bg-primary border-primary",
        "hover:bg-primary/90 hover:border-primary/90",
        "dark:bg-primary dark:border-primary dark:text-primary-content",
        "dark:hover:bg-primary/90 dark:hover:border-primary/90"
      ],
      "secondary" => [
        "btn-secondary",
        "text-secondary-content bg-secondary border-secondary",
        "hover:bg-secondary/90 hover:border-secondary/90",
        "dark:bg-secondary dark:border-secondary dark:text-secondary-content",
        "dark:hover:bg-secondary/90 dark:hover:border-secondary/90"
      ],
      "info" => [
        "btn-info",
        "text-info-content bg-info border-info",
        "hover:bg-info/90 hover:border-info/90",
        "dark:bg-info dark:border-info dark:text-info-content",
        "dark:hover:bg-info/90 dark:hover:border-info/90"
      ],
      "success" => [
        "btn-success",
        "text-success-content bg-success border-success",
        "hover:bg-success/90 hover:border-success/90",
        "dark:bg-success dark:border-success dark:text-success-content",
        "dark:hover:bg-success/90 dark:hover:border-success/90"
      ],
      "warning" => [
        "btn-warning",
        "text-warning-content bg-warning border-warning",
        "hover:bg-warning/90 hover:border-warning/90",
        "dark:bg-warning dark:border-warning dark:text-warning-content",
        "dark:hover:bg-warning/90 dark:hover:border-warning/90"
      ],
      "error" => [
        "btn-error",
        "text-error-content bg-error border-error",
        "hover:bg-error/90 hover:border-error/90",
        "dark:bg-error dark:border-error dark:text-error-content",
        "dark:hover:bg-error/90 dark:hover:border-error/90"
      ],
      nil => [
        "btn-primary btn-soft",
        "text-base-content bg-base-200 border-base-300",
        "hover:bg-base-300 hover:border-base-300",
        "dark:text-base-content dark:bg-base-200 dark:border-base-300",
        "dark:hover:bg-base-300 dark:hover:border-base-300"
      ]
    }

    sizes = %{
      "sm" => "btn-sm px-2 py-1 text-xs",
      "md" => "btn-md px-3 py-2 text-sm",
      "lg" => "btn-lg px-4 py-3 text-base"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        [
          "btn",
          "rounded-full",
          "border",
          "font-medium",
          "transition-all duration-200",
          "focus:outline-none focus:ring-2 focus:ring-offset-2",
          "dark:focus:ring-offset-base-100",
          Map.fetch!(variants, assigns[:variant]),
          Map.fetch!(sizes, assigns[:size])
        ]
      end)

    if assigns.rest[:href] || assigns.rest[:navigate] || assigns.rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a header with hero styling, containing an avatar image, channel name, and description.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions
  attr :banner_url, :string, required: true

  # Optional Tailwind height classes to control the banner height (defaults to ~256-320px responsive)
  attr :height_class, :string, default: "h-64 md:h-80"
  # Optional overlay opacity class override (e.g. "bg-black/30"). Provided for flexibility.
  attr :overlay_class, :string, default: "bg-black/40"

  # Banner sizing strategy: "static" (use height_class), "fluid" (viewport clamp), "ratio" (aspect box)
  attr :mode, :string, values: ~w(static fluid ratio), default: "static"
  # Aspect ratio (only used when mode=="ratio") expressed as width/height, e.g. "21/5"
  attr :ratio, :string, default: "21/5"

  def hero_header(assigns) do
    assigns = assign(assigns, :banner_box_class, banner_box_class(assigns))

    ~H"""
    <header class={[@actions != [] && "flex flex-row items-center justify-between gap-6", "pb-4"]}>
      <div class={["w-full relative overflow-hidden rounded-lg", @banner_box_class]}>
        <img
          src={@banner_url}
          alt="Channel banner"
          class={[
            @mode == "ratio" && "absolute inset-0 w-full h-full",
            @mode != "ratio" && "w-full h-full",
            "object-cover object-center select-none pointer-events-none"
          ]}
          draggable="false"
        />
        <div class={["absolute inset-0", @overlay_class]}></div>
        <div class="absolute inset-0 flex items-center px-4">
          <div class="w-full max-w-6xl mx-auto flex flex-col md:flex-row md:items-center md:justify-between gap-6 text-white">
            <div class="flex-1 space-y-4 text-center md:text-left">
              {render_slot(@inner_block)}
            </div>
            <div class="flex flex-wrap justify-center md:justify-end gap-2 md:min-w-[12rem]">
              {render_slot(@actions)}
            </div>
          </div>
        </div>
      </div>
    </header>
    """
  end

  # -- Private helpers -------------------------------------------------------
  defp banner_box_class(%{mode: "static", height_class: hc}), do: hc
  defp banner_box_class(%{mode: "fluid"}), do: "h-[clamp(16rem,40vh,30rem)]"

  defp banner_box_class(%{mode: "ratio", ratio: ratio}),
    do: "relative aspect-[#{ratio}] max-h-[30rem] min-h-[16rem]"

  @doc """
  Renders a download progress bar with speed and ETA information.

  Used on the download queue page to show real-time download progress.
  When `pct` is nil, renders an indeterminate animated bar.

  ## Examples

      <.download_progress_bar pct={45.2} speed="12.5MiB/s" eta="00:42" />
      <.download_progress_bar pct={nil} />
      <.download_progress_bar pct={100.0} post_processing?={true} />
  """
  attr :pct, :float, default: nil
  attr :speed, :string, default: nil
  attr :eta, :string, default: nil
  attr :post_processing?, :boolean, default: false
  attr :class, :string, default: nil

  def download_progress_bar(assigns) do
    pct =
      case assigns.pct do
        pct when is_number(pct) ->
          pct
          |> Kernel.*(1.0)
          |> max(0.0)
          |> min(100.0)
          |> Float.round(1)

        _ ->
          nil
      end

    status_text =
      cond do
        assigns.post_processing? -> gettext("Post-processing...")
        is_nil(pct) -> gettext("Downloading...")
        true -> "#{pct}%"
      end

    meta_text =
      [assigns.speed, if(assigns.eta, do: gettext("ETA %{eta}", eta: assigns.eta))]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" • ")

    fill_class =
      cond do
        assigns.post_processing? -> "bg-warning animate-pulse"
        pct == 100.0 -> "bg-success"
        true -> "bg-primary"
      end

    bar_width =
      cond do
        assigns.post_processing? and is_nil(pct) -> 100.0
        is_nil(pct) -> nil
        true -> pct
      end

    assigns =
      assigns
      |> assign(:pct, pct)
      |> assign(:status_text, status_text)
      |> assign(:meta_text, meta_text)
      |> assign(:fill_class, fill_class)
      |> assign(:bar_width, bar_width)

    ~H"""
    <div class={["w-full space-y-1.5", @class]}>
      <div class="relative w-full h-2 overflow-hidden rounded-full bg-base-300">
        <%= if is_nil(@bar_width) do %>
          <div class="absolute inset-y-0 left-0 w-2/5 rounded-full bg-linear-to-r from-transparent via-primary to-transparent animate-pulse">
          </div>
        <% else %>
          <div
            class={["h-full rounded-full transition-all duration-300", @fill_class]}
            style={"width: #{@bar_width}%"}
          >
          </div>
        <% end %>
      </div>
      <div class="flex items-center justify-between gap-3 text-xs text-base-content/70">
        <span class="truncate font-medium">{@status_text}</span>
        <span :if={@meta_text != ""} class="shrink-0 text-right">
          {@meta_text}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders a thin progress bar showing a ratio of completed / total.
  Used for playlist download progress indicators (Sonarr-style).

  ## Examples

      <.progress_bar completed={3} total={10} />
  """
  attr :completed, :integer, required: true
  attr :total, :integer, required: true
  attr :class, :string, default: nil

  def progress_bar(assigns) do
    pct =
      if assigns.total > 0,
        do: Float.round(assigns.completed / assigns.total * 100, 1),
        else: 0.0

    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class={["w-full bg-base-300 rounded-full h-1.5 overflow-hidden", @class]}>
      <div
        class={[
          "h-full rounded-full transition-all duration-300",
          if(@pct == 100, do: "bg-success", else: "bg-primary")
        ]}
        style={"width: #{@pct}%"}
        title={"#{@completed}/#{@total} downloaded (#{@pct}%)"}
      >
      </div>
    </div>
    """
  end

  @doc """
  Renders a styled badge for video download state. `tooltip` (when truthy) sets
  both `title` and `aria-label` so status detail is available to sighted and
  assistive-technology users alike without adding extra table text.

  ## Examples

      <.download_status_badge state={:downloaded} />
      <.download_status_badge state={:import_failed} tooltip="Import failed: disk full" />
  """
  attr :state, :atom, required: true
  attr :tooltip, :string, default: nil

  def download_status_badge(assigns) do
    ~H"""
    <%= case @state do %>
      <% :available -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-base-200 text-base-content/60"
        >
          <.icon name="hero-cloud-arrow-down" class="size-3.5" /> Available
        </span>
      <% :queued -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-info/15 text-info"
        >
          <.icon name="hero-clock" class="size-3.5" /> Queued
        </span>
      <% :downloading -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-warning/15 text-warning"
        >
          <.icon name="hero-arrow-path" class="size-3.5 animate-spin" /> Downloading
        </span>
      <% :downloaded -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-success/15 text-success"
        >
          <.icon name="hero-check-badge" class="size-3.5" /> Downloaded
        </span>
      <% :missing -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-error/15 text-error"
        >
          <.icon name="hero-exclamation-triangle" class="size-3.5" /> Missing
        </span>
      <% :importing -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-warning/15 text-warning"
        >
          <.icon name="hero-arrow-path" class="size-3.5 motion-safe:animate-spin" /> Importing
        </span>
      <% :import_failed -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-error/15 text-error"
        >
          <.icon name="hero-x-circle" class="size-3.5" /> Import failed
        </span>
      <% _ -> %>
        <span
          title={@tooltip}
          aria-label={@tooltip}
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-base-200 text-base-content/40"
        >
          <.icon name="hero-question-mark-circle" class="size-3.5" /> Unknown
        </span>
    <% end %>
    """
  end

  @doc """
  Renders a reusable video table for channel/playlist views.
  Used in the channel show page for both playlist videos and all-videos sections.

  ## Examples

      <.video_table id="playlist-videos-1" videos={playlist.videos} channel_id={@channel.id} />
  """
  attr :id, :string, required: true
  attr :videos, :list, required: true
  attr :channel_id, :any, required: true

  def video_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm">
        <thead>
          <tr class="text-xs text-base-content/50 uppercase tracking-wider">
            <th class="w-20">Thumb</th>
            <th>Title</th>
            <th class="w-28">Upload Date</th>
            <th class="w-40">Status</th>
            <th class="w-32">Actions</th>
          </tr>
        </thead>
        <tbody id={@id}>
          <%= for video <- @videos do %>
            <tr
              id={ImportModal.row_id(@id, video.id)}
              tabindex="-1"
              class="hover:bg-base-200/50 transition-colors"
            >
              <td>
                <%= if video.thumbnail_url do %>
                  <img
                    src={video.thumbnail_url}
                    alt={video.title}
                    class="w-16 h-9 rounded object-cover bg-base-300"
                    loading="lazy"
                  />
                <% else %>
                  <div class="w-16 h-9 rounded bg-base-300 flex items-center justify-center">
                    <.icon name="hero-play" class="size-4 text-base-content/30" />
                  </div>
                <% end %>
              </td>
              <td class="max-w-xs">
                <span class="text-sm font-medium truncate block">{video.title}</span>
              </td>
              <td>
                <span class="text-xs text-base-content/60">{video.upload_date}</span>
              </td>
              <td>
                <div class="flex flex-wrap items-center gap-1.5">
                  <.download_status_badge
                    state={video.download_state}
                    tooltip={
                      video.download_state == :import_failed && "Import failed: #{video.import_error}"
                    }
                  />
                  <span
                    :if={video.download_state == :import_failed and not recovery_empty?(video)}
                    title={recovery_tooltip("Source recovery needed", video)}
                    aria-label={recovery_tooltip("Source recovery needed", video)}
                    class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-warning/15 text-warning"
                  >
                    <.icon name="hero-wrench-screwdriver" class="size-3.5" /> Source recovery needed
                  </span>
                  <span
                    :if={video.download_state == :downloaded and not recovery_empty?(video)}
                    title={recovery_tooltip("Source cleanup needed", video)}
                    aria-label={recovery_tooltip("Source cleanup needed", video)}
                    class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-warning/15 text-warning"
                  >
                    <.icon name="hero-wrench-screwdriver" class="size-3.5" /> Source cleanup needed
                  </span>
                  <span
                    :if={video.is_blocklisted}
                    class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-error/15 text-error"
                  >
                    <.icon name="hero-no-symbol" class="size-3.5" /> Blocked
                  </span>
                </div>
              </td>
              <td>
                <div class="flex flex-wrap items-center gap-1">
                  <%= if video.download_state == :downloaded do %>
                    <button
                      title="Delete downloaded video"
                      phx-click="delete-video"
                      phx-value-id={video.id}
                      class="btn btn-ghost btn-xs text-error hover:bg-error/10"
                      data-confirm="Are you sure you want to delete this video file?"
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  <% else %>
                    <%= if download_eligible?(video) do %>
                      <button
                        title="Queue Download"
                        phx-click="queue-download"
                        phx-value-id={video.id}
                        phx-value-channel-id={@channel_id}
                        class="btn btn-ghost btn-xs text-primary hover:bg-primary/10"
                      >
                        <.icon name="hero-arrow-down-tray" class="size-3.5" />
                      </button>
                    <% end %>
                  <% end %>

                  <%= if import_eligible?(video) do %>
                    <button
                      id={ImportModal.import_button_id(@id, video.id)}
                      title="Import existing file"
                      aria-label="Import existing file"
                      phx-click="open-video-import"
                      phx-value-id={video.id}
                      phx-value-table-id={@id}
                      class="btn btn-ghost btn-xs text-info hover:bg-info/10"
                    >
                      <.icon name="hero-folder-arrow-down" class="size-3.5" />
                    </button>
                  <% end %>
                  <%= if import_unavailable?(video) do %>
                    <button
                      type="button"
                      title="Import unavailable: refresh video metadata to obtain an upload date"
                      aria-label="Import unavailable: refresh video metadata to obtain an upload date"
                      disabled
                      class="btn btn-ghost btn-xs text-base-content/30"
                    >
                      <.icon name="hero-folder-arrow-down" class="size-3.5" />
                    </button>
                  <% end %>
                  <%= if retry_recovery_eligible?(video) do %>
                    <button
                      id={ImportModal.retry_button_id(@id, video.id)}
                      title={
                        if(video.download_state == :import_failed,
                          do: "Retry source recovery",
                          else: "Retry source cleanup"
                        )
                      }
                      phx-click="retry-import-recovery"
                      phx-value-id={video.id}
                      class="btn btn-ghost btn-xs text-warning hover:bg-warning/10"
                    >
                      <.icon name="hero-arrow-path-rounded-square" class="size-3.5" />
                    </button>
                  <% end %>

                  <%= if video.is_blocklisted do %>
                    <button
                      title="Remove video from blocklist"
                      phx-click="unblocklist-video"
                      phx-value-id={video.id}
                      class="btn btn-ghost btn-xs text-success hover:bg-success/10"
                    >
                      <.icon name="hero-check-circle" class="size-3.5" />
                    </button>
                  <% else %>
                    <button
                      title="Add video to blocklist"
                      phx-click="blocklist-video"
                      phx-value-id={video.id}
                      class="btn btn-ghost btn-xs text-error hover:bg-error/10"
                    >
                      <.icon name="hero-no-symbol" class="size-3.5" />
                    </button>
                  <% end %>
                </div>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end
end
