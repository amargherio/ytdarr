defmodule YtdarrWeb.ChannelLive.ImportModal do
  @moduledoc """
  Function-component modal for importing an already-downloaded file from the
  server filesystem into a video's canonical media location.

  Owns no process state of its own: `State` is plain data carried in the
  parent `ChannelLive.Show` socket assigns, and every mutation here is a pure
  transformation returning a new `State.t()`. Rendering, focus management,
  and the inert app-shell boundary are driven declaratively from that state.
  """
  use Phoenix.Component

  import YtdarrWeb.CoreComponents, only: [icon: 1, input: 1]

  alias Phoenix.LiveView.JS
  alias Ytdarr.Imports.SafeMessage
  alias Ytdarr.Media.FileBrowser.Page
  alias Ytdarr.Media.VideoImport.Preview

  @state_changed_message "This video's state changed in another session. Close Import and try again."

  @stale_reasons ~w(source_changed destination_changed invalid_sidecar_selection missing_upload_date
                    unsupported_extension destination_exists)a
  @state_changed_reasons ~w(video_not_importable import_conflict)a

  defmodule State do
    @moduledoc """
    Modal state carried in the parent LiveView's `:import_modal` assign.
    `nil` in the parent assign means the modal is closed.
    """

    @enforce_keys [
      :token,
      :video_id,
      :channel_id,
      :video_title,
      :table_id,
      :row_selector,
      :opener_selector,
      :fallback_selector,
      :phase,
      :page,
      :query,
      :show_hidden?,
      :list_seq,
      :preview,
      :selected_sidecar_ids,
      :selected_entry_id,
      :error,
      :filter_form
    ]
    defstruct @enforce_keys

    @type phase :: :listing | :browsing | :inspecting | :ready | :queueing | :state_changed

    @type t :: %__MODULE__{
            token: String.t(),
            video_id: integer(),
            channel_id: integer(),
            video_title: String.t(),
            table_id: String.t(),
            row_selector: String.t(),
            opener_selector: String.t(),
            fallback_selector: String.t(),
            phase: phase(),
            page: Page.t() | nil,
            query: String.t(),
            show_hidden?: boolean(),
            list_seq: non_neg_integer(),
            preview: Preview.t() | nil,
            selected_sidecar_ids: MapSet.t(String.t()),
            selected_entry_id: String.t() | nil,
            error: String.t() | nil,
            filter_form: Phoenix.HTML.Form.t()
          }
  end

  # ---------------------------------------------------------------------------
  # Stable DOM ids
  # ---------------------------------------------------------------------------

  @spec row_id(String.t(), integer()) :: String.t()
  def row_id(table_id, video_id), do: "video-row-#{table_id}-#{video_id}"

  @spec import_button_id(String.t(), integer()) :: String.t()
  def import_button_id(table_id, video_id), do: "import-video-#{table_id}-#{video_id}"

  @spec retry_button_id(String.t(), integer()) :: String.t()
  def retry_button_id(table_id, video_id), do: "retry-import-recovery-#{table_id}-#{video_id}"

  @doc "The section-toggle control id used as this table's modal-close fallback focus target."
  @spec fallback_id(String.t()) :: String.t()
  def fallback_id("all-videos"), do: "toggle-all-videos"
  def fallback_id("videos-" <> playlist_id), do: "toggle-playlist-#{playlist_id}"
  def fallback_id(_table_id), do: "toggle-all-videos"

  @doc "The safe message used to disable the modal when its video's lifecycle state changes elsewhere."
  @spec state_changed_message() :: String.t()
  def state_changed_message, do: @state_changed_message

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @spec new(map(), String.t(), String.t(), String.t(), String.t()) :: State.t()
  def new(video, table_id, row_selector, opener_selector, fallback_selector) do
    %State{
      token: random_token(),
      video_id: video.id,
      channel_id: video.channel_id,
      video_title: video.title,
      table_id: table_id,
      row_selector: row_selector,
      opener_selector: opener_selector,
      fallback_selector: fallback_selector,
      phase: :listing,
      page: nil,
      query: "",
      show_hidden?: false,
      list_seq: 0,
      preview: nil,
      selected_sidecar_ids: MapSet.new(),
      selected_entry_id: nil,
      error: nil,
      filter_form: filter_form("", false)
    }
  end

  # ---------------------------------------------------------------------------
  # Directory navigation (deterministic reset rules)
  # ---------------------------------------------------------------------------

  @doc "Folder / breadcrumb / Up / root: clears query, resets to page 1, preserves hidden."
  @spec navigate_to(State.t(), Path.t()) :: {State.t(), Path.t(), keyword()}
  def navigate_to(%State{} = state, path) when is_binary(path) do
    new_state = %{
      state
      | phase: :listing,
        query: "",
        error: nil,
        filter_form: filter_form("", state.show_hidden?)
    }

    {new_state, path, [query: "", show_hidden?: state.show_hidden?, page: 1]}
  end

  @doc "Filter/hidden change: preserves the other of the two, always resets to page 1."
  @spec apply_filter_change(State.t(), String.t(), boolean()) :: {State.t(), Path.t(), keyword()}
  def apply_filter_change(%State{} = state, query, show_hidden?)
      when is_binary(query) and is_boolean(show_hidden?) do
    new_state = %{
      state
      | phase: :listing,
        query: query,
        show_hidden?: show_hidden?,
        error: nil,
        filter_form: filter_form(query, show_hidden?)
    }

    {new_state, current_path(state), [query: query, show_hidden?: show_hidden?, page: 1]}
  end

  @doc "Page change: preserves query/hidden, rejects an out-of-range target page."
  @spec change_page(State.t(), integer()) :: {State.t(), Path.t(), keyword()} | :out_of_range
  def change_page(%State{page: %Page{total_pages: total_pages}} = state, page)
      when is_integer(page) and page >= 1 and page <= total_pages do
    new_state = %{state | phase: :listing, error: nil}

    {new_state, current_path(state),
     [query: state.query, show_hidden?: state.show_hidden?, page: page]}
  end

  def change_page(%State{}, _page), do: :out_of_range

  @spec current_path(State.t()) :: Path.t()
  def current_path(%State{page: %Page{path: path}}), do: path
  def current_path(%State{}), do: "/"

  @doc "Applies an async directory listing result. Failure leaves the last successful page in place."
  @spec apply_list_result(State.t(), {:ok, Page.t()} | {:error, term()}) :: State.t()
  def apply_list_result(%State{} = state, {:ok, %Page{} = page}) do
    %{state | phase: :browsing, page: page, error: nil}
  end

  def apply_list_result(%State{} = state, {:error, reason}) do
    %{state | phase: :browsing, error: browse_error_message(reason)}
  end

  # ---------------------------------------------------------------------------
  # Inspection
  # ---------------------------------------------------------------------------

  @spec start_inspection(State.t(), String.t()) :: State.t()
  def start_inspection(%State{} = state, entry_id) when is_binary(entry_id) do
    %{
      state
      | phase: :inspecting,
        preview: nil,
        selected_sidecar_ids: MapSet.new(),
        selected_entry_id: entry_id,
        error: nil
    }
  end

  @spec apply_inspection_result(State.t(), {:ok, Preview.t()} | {:error, term()}) :: State.t()
  def apply_inspection_result(%State{} = state, {:ok, %Preview{} = preview}) do
    %{
      state
      | phase: :ready,
        preview: preview,
        selected_sidecar_ids: MapSet.new(preview.sidecars, & &1.id),
        error: nil
    }
  end

  def apply_inspection_result(%State{} = state, {:error, reason}) do
    %{state | phase: :browsing, preview: nil, error: SafeMessage.for(reason)}
  end

  @doc "Choose another: cancels inspection, clears preview/error, returns to the current directory."
  @spec clear_selection(State.t()) :: State.t()
  def clear_selection(%State{} = state) do
    %{state | phase: :browsing, preview: nil, selected_sidecar_ids: MapSet.new(), error: nil}
  end

  @spec replace_selected_sidecars(State.t(), [String.t()]) :: State.t()
  def replace_selected_sidecars(%State{preview: nil} = state, _ids), do: state

  def replace_selected_sidecars(%State{preview: %Preview{sidecars: sidecars}} = state, ids)
      when is_list(ids) do
    known_ids = MapSet.new(sidecars, & &1.id)
    %{state | selected_sidecar_ids: ids |> MapSet.new() |> MapSet.intersection(known_ids)}
  end

  # ---------------------------------------------------------------------------
  # Confirm
  # ---------------------------------------------------------------------------

  @spec start_queueing(State.t()) :: State.t()
  def start_queueing(%State{} = state), do: %{state | phase: :queueing, error: nil}

  @doc """
  Categorizes an enqueue failure: staleness clears the preview and requires
  reselection, a changed-video-state error disables the modal, and anything
  else is treated as a transient, retryable enqueue error.
  """
  @spec apply_queue_error(State.t(), term()) :: State.t()
  def apply_queue_error(%State{} = state, reason) do
    cond do
      reason_in?(reason, @state_changed_reasons) ->
        invalidate(state, @state_changed_message)

      reason_in?(reason, @stale_reasons) ->
        %{
          state
          | phase: :browsing,
            preview: nil,
            selected_sidecar_ids: MapSet.new(),
            error: SafeMessage.for(reason)
        }

      true ->
        %{state | phase: :ready, error: SafeMessage.for(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Lifecycle invalidation (Imports PubSub gating)
  # ---------------------------------------------------------------------------

  @spec invalidate(State.t(), String.t()) :: State.t()
  def invalidate(%State{} = state, message) when is_binary(message) do
    %{
      state
      | phase: :state_changed,
        preview: nil,
        selected_sidecar_ids: MapSet.new(),
        error: message
    }
  end

  @doc "The async keys currently owned by this modal state, for cancellation on teardown/invalidation."
  @spec async_keys(State.t()) :: [term()]
  def async_keys(%State{token: token, list_seq: list_seq}) do
    [{:list_video_import, token, list_seq}, {:inspect_video_import, token}]
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  attr :state, State, required: true

  def modal(assigns) do
    ~H"""
    <div
      id="video-import-overlay"
      class="fixed inset-0 z-[60] flex items-center justify-center"
      phx-window-keydown="close-video-import"
      phx-key="escape"
      phx-value-token={@state.token}
      phx-remove={teardown_js(@state)}
    >
      <div id="video-import-backdrop" class="absolute inset-0 bg-base-content/40"></div>

      <.focus_wrap
        id="video-import-dialog"
        class="relative z-[61] flex h-[calc(100dvh-1rem)] w-[calc(100vw-1rem)] flex-col overflow-hidden border border-base-300 bg-base-100 sm:h-auto sm:max-h-[calc(100dvh-2rem)] sm:max-w-5xl sm:rounded-xl"
        role="dialog"
        aria-modal="true"
        aria-labelledby="video-import-title"
        aria-describedby="video-import-description"
        phx-mounted={JS.focus(to: "#video-import-close")}
      >
        <header class="flex items-start justify-between gap-3 border-b border-base-300 px-4 py-3 flex-shrink-0">
          <div class="min-w-0">
            <h2 id="video-import-title" class="text-base font-semibold truncate">
              Import "{@state.video_title}"
            </h2>
            <p id="video-import-description" class="text-xs text-base-content/60 mt-0.5">
              Choose an existing file already on the server to place as this episode.
            </p>
          </div>
          <button
            type="button"
            id="video-import-close"
            phx-click="close-video-import"
            phx-value-token={@state.token}
            class="btn btn-ghost btn-sm btn-square flex-shrink-0"
            title="Close"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>

        <div class="flex-1 overflow-y-auto p-4 space-y-4">
          <p
            :if={@state.error && @state.phase != :state_changed}
            id="video-import-error"
            role="alert"
            class="alert alert-error text-sm py-2"
          >
            <.icon name="hero-exclamation-circle" class="size-4 flex-shrink-0" />
            <span>{@state.error}</span>
          </p>

          <.state_changed_panel :if={@state.phase == :state_changed} state={@state} />
          <.preview_panel :if={@state.phase in [:ready, :queueing]} state={@state} />
          <.browser_panel :if={@state.phase in [:listing, :browsing, :inspecting]} state={@state} />
        </div>

        <footer class="flex items-center justify-end gap-2 border-t border-base-300 px-4 py-3 flex-shrink-0">
          <button
            type="button"
            id="video-import-cancel"
            phx-click="close-video-import"
            phx-value-token={@state.token}
            class="btn btn-ghost btn-sm"
          >
            Cancel
          </button>
        </footer>
      </.focus_wrap>
    </div>
    """
  end

  attr :state, State, required: true

  defp state_changed_panel(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 py-10 text-center">
      <.icon name="hero-exclamation-triangle" class="size-8 text-warning" />
      <p class="text-sm text-base-content/70 max-w-sm">{@state.error}</p>
    </div>
    """
  end

  attr :state, State, required: true

  defp browser_panel(assigns) do
    ~H"""
    <div class="space-y-3">
      <nav aria-label="Breadcrumb" class="flex flex-wrap items-center gap-1 text-sm">
        <button
          type="button"
          id="video-import-root"
          phx-click="browse-import-directory"
          phx-value-token={@state.token}
          phx-value-path="/"
          class="btn btn-ghost btn-xs btn-square"
          title="Root"
          aria-label="Root"
        >
          <.icon name="hero-home" class="size-3.5" />
        </button>
        <%= for {crumb, index} <- Enum.with_index(breadcrumbs(@state)) do %>
          <.icon name="hero-chevron-right" class="size-3 text-base-content/30 flex-shrink-0" />
          <button
            type="button"
            id={"video-import-breadcrumb-#{index}"}
            phx-click="browse-import-directory"
            phx-value-token={@state.token}
            phx-value-path={crumb.path}
            class="btn btn-ghost btn-xs truncate max-w-32"
          >
            {crumb.label}
          </button>
        <% end %>
        <button
          :if={@state.page && @state.page.parent_path}
          type="button"
          id="video-import-up"
          phx-click="browse-import-directory"
          phx-value-token={@state.token}
          phx-value-path={@state.page.parent_path}
          class="btn btn-ghost btn-xs ml-auto gap-1"
        >
          <.icon name="hero-arrow-up" class="size-3.5" /> Up
        </button>
      </nav>

      <.form
        for={@state.filter_form}
        id="video-import-filter-form"
        phx-change="filter-import-directory"
        class="flex items-center gap-3"
      >
        <input type="hidden" name="token" value={@state.token} />
        <.input
          field={@state.filter_form[:query]}
          type="text"
          placeholder="Filter this folder…"
          phx-debounce="200"
          class="input input-sm flex-1"
        />
        <label class="label cursor-pointer gap-2 text-sm whitespace-nowrap">
          <input
            type="checkbox"
            name={@state.filter_form[:show_hidden].name}
            value="true"
            checked={@state.show_hidden?}
            class="checkbox checkbox-sm"
          /> Show hidden
        </label>
      </.form>

      <div class="relative border border-base-300 rounded-lg overflow-hidden">
        <div
          :if={@state.phase == :listing}
          class="absolute inset-0 z-10 flex items-center justify-center bg-base-100/60"
        >
          <.icon name="hero-arrow-path" class="size-5 motion-safe:animate-spin text-base-content/40" />
        </div>

        <%= if @state.page do %>
          <ul class="divide-y divide-base-200 max-h-96 overflow-y-auto">
            <li
              :if={@state.page.entries == []}
              class="px-3 py-6 text-center text-sm text-base-content/50"
            >
              This folder is empty.
            </li>
            <li :for={entry <- @state.page.entries}>
              <button
                :if={entry.kind == :directory}
                type="button"
                id={"video-import-folder-#{entry.id}"}
                tabindex="-1"
                phx-click="browse-import-directory"
                phx-value-token={@state.token}
                phx-value-path={entry.path}
                class="flex w-full items-center gap-2 px-3 py-2 text-sm hover:bg-base-200 text-left"
              >
                <.icon name="hero-folder" class="size-4 text-base-content/40 flex-shrink-0" />
                <span class="truncate">{entry.name}</span>
              </button>
              <button
                :if={entry.kind == :video}
                type="button"
                id={"video-import-file-#{entry.id}"}
                tabindex="-1"
                phx-click="select-import-file"
                phx-value-token={@state.token}
                phx-value-id={entry.id}
                phx-mounted={
                  if entry.id == @state.selected_entry_id,
                    do: JS.focus(to: "#video-import-file-#{entry.id}")
                }
                class="flex w-full items-center justify-between gap-2 px-3 py-2 text-sm hover:bg-base-200 text-left"
              >
                <span class="flex items-center gap-2 min-w-0">
                  <.icon name="hero-film" class="size-4 text-base-content/40 flex-shrink-0" />
                  <span class="truncate">{entry.name}</span>
                </span>
                <span class="text-xs text-base-content/40 flex-shrink-0">{format_bytes(entry.size)}</span>
              </button>
            </li>
          </ul>

          <div class="flex items-center justify-between gap-2 border-t border-base-200 px-3 py-2">
            <span class="text-xs text-base-content/50">
              Page {@state.page.page} of {@state.page.total_pages} &middot; {@state.page.total_entries} items
            </span>
            <div class="flex items-center gap-1">
              <button
                type="button"
                id="video-import-page-previous"
                disabled={@state.page.page <= 1}
                phx-click="change-import-page"
                phx-value-token={@state.token}
                phx-value-page={@state.page.page - 1}
                class="btn btn-ghost btn-xs btn-square"
                aria-label="Previous page"
              >
                <.icon name="hero-chevron-left" class="size-3.5" />
              </button>
              <button
                type="button"
                id="video-import-page-next"
                disabled={@state.page.page >= @state.page.total_pages}
                phx-click="change-import-page"
                phx-value-token={@state.token}
                phx-value-page={@state.page.page + 1}
                class="btn btn-ghost btn-xs btn-square"
                aria-label="Next page"
              >
                <.icon name="hero-chevron-right" class="size-3.5" />
              </button>
            </div>
          </div>
        <% else %>
          <div class="px-3 py-10 text-center text-sm text-base-content/50">Loading…</div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :state, State, required: true

  defp preview_panel(assigns) do
    ~H"""
    <div class="space-y-4">
      <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5 text-sm">
        <dt class="text-base-content/50">Source</dt>
        <dd class="font-mono text-xs break-all">{@state.preview.source.source_path}</dd>
        <dt class="text-base-content/50">Destination</dt>
        <dd class="font-mono text-xs break-all">{@state.preview.destination.media_path}</dd>
        <dt class="text-base-content/50">Size</dt>
        <dd>{format_bytes(@state.preview.source.fingerprint.size)}</dd>
        <dt class="text-base-content/50">Quality</dt>
        <dd>{@state.preview.quality || "Unknown"}</dd>
      </dl>

      <p :if={@state.preview.source_nfo} class="flex items-start gap-1.5 text-xs text-base-content/60">
        <.icon name="hero-information-circle" class="size-3.5 flex-shrink-0 mt-0.5" />
        <span>
          The existing
          <span class="font-mono">{Path.basename(@state.preview.source_nfo.source_path)}</span>
          will be replaced with corrected metadata.
        </span>
      </p>

      <form
        id="video-import-confirm-form"
        phx-change="toggle-import-sidecar"
        phx-submit="confirm-video-import"
      >
        <input type="hidden" name="token" value={@state.token} />

        <fieldset
          :if={@state.preview.sidecars != []}
          class="space-y-1.5 border border-base-200 rounded-lg p-3"
        >
          <legend class="px-1 text-xs font-medium text-base-content/60">Also import</legend>
          <label
            :for={sidecar <- @state.preview.sidecars}
            class="flex items-center gap-2 text-sm cursor-pointer"
          >
            <input
              type="checkbox"
              id={"video-import-sidecar-#{sidecar.id}"}
              name="import[sidecar_ids][]"
              value={sidecar.id}
              checked={MapSet.member?(@state.selected_sidecar_ids, sidecar.id)}
              class="checkbox checkbox-sm"
            />
            <span class="truncate">{Path.basename(sidecar.source_path)}</span>
            <span class="text-xs text-base-content/40">({sidecar_kind_label(sidecar.kind)})</span>
          </label>
        </fieldset>

        <div class="flex justify-end gap-2 pt-3">
          <button
            type="button"
            id="video-import-choose-another"
            phx-click="clear-import-selection"
            phx-value-token={@state.token}
            class="btn btn-ghost btn-sm"
          >
            Choose another
          </button>
          <button
            type="submit"
            id="video-import-confirm"
            phx-disable-with="Queueing import…"
            disabled={@state.phase == :queueing}
            class="btn btn-primary btn-sm gap-1"
          >
            <.icon name="hero-folder-arrow-down" class="size-4" /> Import
          </button>
        </div>
      </form>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp breadcrumbs(%State{page: %Page{breadcrumbs: breadcrumbs}}), do: breadcrumbs
  defp breadcrumbs(%State{}), do: []

  defp filter_form(query, show_hidden?) do
    Phoenix.Component.to_form(%{"query" => query, "show_hidden" => show_hidden?}, as: "filter")
  end

  defp teardown_js(%State{} = state) do
    %JS{}
    |> JS.remove_attribute("inert", to: "#app-shell")
    |> JS.remove_attribute("aria-hidden", to: "#app-shell")
    |> JS.focus(to: state.fallback_selector)
    |> JS.focus(to: state.row_selector)
    |> JS.focus(to: state.opener_selector)
  end

  defp random_token do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp reason_in?(reason, candidates) do
    text = inspect(reason)
    Enum.any?(candidates, &String.contains?(text, Atom.to_string(&1)))
  end

  defp browse_error_message(:directory_not_found), do: "That folder is no longer available."

  defp browse_error_message(:directory_not_readable),
    do: "Ytdarr cannot read that folder. Check its permissions."

  defp browse_error_message(:not_a_directory), do: "That path is not a folder."
  defp browse_error_message(:page_out_of_range), do: "That page no longer exists."

  defp browse_error_message(_reason),
    do: "Ytdarr could not list that folder. Check the server logs and try again."

  defp format_bytes(nil), do: "—"

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp sidecar_kind_label(:subtitle), do: "subtitle"
  defp sidecar_kind_label(:artwork), do: "artwork"
  defp sidecar_kind_label(_kind), do: "file"
end
