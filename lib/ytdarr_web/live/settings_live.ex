defmodule YtdarrWeb.SettingsLive do
  use YtdarrWeb, :live_view

  alias Ytdarr.Settings
  # alias Ytdarr.Settings.{QualityProfile, YtDlpParamSet, MediaRootFolder}

  # -----------------
  # Mount / Params
  # -----------------
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
    |> assign(:current_scope, nil)
     |> assign(:tab, tab_from(params))
     |> load_data()}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :tab, tab_from(params))}
  end

  defp tab_from(%{"tab" => t}) when t in ~w(media profiles youtube downloader), do: String.to_existing_atom(t)
  defp tab_from(_), do: :media

  # -----------------
  # Data loading & forms
  # -----------------
  defp load_data(socket) do
    cfg = Settings.effective_config()

    media_changeset = Settings.media_settings_changeset()
    media_form = to_form(media_changeset, as: :media)

    youtube_changeset = Settings.youtube_settings_changeset()
    youtube_form =
      youtube_changeset
      |> Map.update!(:changes, fn ch -> Map.put(ch, :api_key, mask_api_key(youtube_changeset.data.api_key)) end)
      |> to_form(as: :youtube)

    profile_form =
      %Settings.QualityProfile{}
      |> Settings.change_quality_profile(%{allow_hdr: true})
      |> to_form(as: :profile)

    param_set_form =
      %Settings.YtDlpParamSet{}
      |> Settings.change_yt_dlp_param_set(%{})
      |> to_form(as: :param_set)

    root_folder_form =
      %Settings.MediaRootFolder{}
      |> Settings.change_media_root_folder(%{})
      |> to_form(as: :root_folder)

    socket
    |> assign(:media_form, media_form)
    |> assign(:youtube_form, youtube_form)
    |> assign(:profile_form, profile_form)
    |> assign(:param_set_form, param_set_form)
    |> assign(:root_folder_form, root_folder_form)
    |> assign(:profiles, cfg.profiles)
    |> assign(:param_sets, cfg.downloader.param_sets)
    |> assign(:root_folders, cfg.media.root_folders)
    |> assign(:default_param_set, cfg.downloader.default_param_set)
  end

  defp mask_api_key(nil), do: nil
  defp mask_api_key(value), do: if(value == "********", do: value, else: "********")

  # -----------------
  # Events (grouped)
  # -----------------
  def handle_event("save-media", %{"media" => params}, socket) do
    changeset = Settings.media_settings_changeset(params)
    if changeset.valid? do
      Settings.put_setting("media.file_naming_template", params["file_naming_template"]) |> ok_ignore()
      Settings.put_setting("media.move_strategy", params["move_strategy"]) |> ok_ignore()
      Settings.put_setting("media.clean_orphans", truthy?(params["clean_orphans"])) |> ok_ignore()
      {:noreply, socket |> put_flash(:info, "Media settings saved") |> load_data()}
    else
      {:noreply, assign(socket, :media_form, to_form(changeset, as: :media))}
    end
  end

  def handle_event("add-root-folder", %{"root_folder" => params}, socket) do
    case Settings.create_media_root_folder(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Root folder added") |> load_data()}
      {:error, cs} -> {:noreply, assign(socket, :root_folder_form, to_form(cs, as: :root_folder))}
    end
  end

  def handle_event("delete-root-folder", %{"id" => id}, socket) do
    Settings.delete_media_root_folder(id) |> ok_ignore()
    {:noreply, socket |> put_flash(:info, "Root folder removed") |> load_data()}
  end

  def handle_event("save-youtube", %{"youtube" => params}, socket) do
    masked = params["api_key"]
    real_api_key = if masked == "********", do: nil, else: masked
    changeset = Settings.youtube_settings_changeset(%{api_key: real_api_key, region: params["region"]})
    if changeset.valid? do
      maybe_set_api_key(params["api_key"]) |> ok_ignore()
      Settings.put_setting("youtube.region", params["region"]) |> ok_ignore()
      {:noreply, socket |> put_flash(:info, "YouTube settings saved") |> load_data()}
    else
      {:noreply, assign(socket, :youtube_form, to_form(changeset, as: :youtube))}
    end
  end

  def handle_event("create-profile", %{"profile" => params}, socket) do
    attrs = normalize_profile_params(params)
    case Settings.create_quality_profile(attrs) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Profile created") |> load_data()}
      {:error, cs} -> {:noreply, assign(socket, :profile_form, to_form(cs, as: :profile))}
    end
  end

  def handle_event("delete-profile", %{"id" => id}, socket) do
    Settings.delete_quality_profile(id) |> ok_ignore()
    {:noreply, socket |> put_flash(:info, "Profile deleted") |> load_data()}
  end

  def handle_event("create-param-set", %{"param_set" => params}, socket) do
    case Settings.create_yt_dlp_param_set(params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Param set created") |> load_data()}
      {:error, cs} -> {:noreply, assign(socket, :param_set_form, to_form(cs, as: :param_set))}
    end
  end

  def handle_event("delete-param-set", %{"id" => id}, socket) do
    Settings.delete_yt_dlp_param_set(id) |> ok_ignore()
    {:noreply, socket |> put_flash(:info, "Param set deleted") |> load_data()}
  end

  defp maybe_set_api_key(""), do: {:ok, :noop}
  defp maybe_set_api_key("********"), do: {:ok, :masked}
  defp maybe_set_api_key(value), do: Settings.put_setting("youtube.primary_api_key", value)

  # -----------------
  # Helpers
  # -----------------
  defp truthy?(v), do: v in [true, "true", "on", "1", 1]
  defp ok_ignore(res), do: res

  defp normalize_profile_params(params) do
    preferred_codecs =
      params["preferred_codecs"]
      |> to_string()
      |> String.split([",", "\n", " "], trim: true)
      |> Enum.uniq()

    params
    |> Map.put("preferred_codecs", preferred_codecs)
  end

  # -----------------
  # Render
  # -----------------
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:settings} current_scope={@current_scope}>
      <.header>
        Settings
        <:subtitle>Configure media management, profiles, YouTube, and downloader</:subtitle>
      </.header>

      <div class="tabs tabs-boxed mb-4">
        <.link patch={~p"/settings?tab=media"} class={["tab", @tab == :media && "tab-active"]}>Media</.link>
        <.link patch={~p"/settings?tab=profiles"} class={["tab", @tab == :profiles && "tab-active"]}>Profiles</.link>
        <.link patch={~p"/settings?tab=youtube"} class={["tab", @tab == :youtube && "tab-active"]}>YouTube</.link>
        <.link patch={~p"/settings?tab=downloader"} class={["tab", @tab == :downloader && "tab-active"]}>Downloader</.link>
      </div>

      <div :if={@tab == :media} id="media" class="space-y-8">
        <.form for={@media_form} id="media-form" phx-submit="save-media">
          <.input field={@media_form[:file_naming_template]} type="text" label="File Naming Template" />
          <.input field={@media_form[:move_strategy]} type="select" label="Move Strategy" options={["copy", "move", "hardlink"]} />
          <.input field={@media_form[:clean_orphans]} type="checkbox" label="Clean Orphans" />
          <.button type="submit" class="mt-2">Save Media Settings</.button>
        </.form>

        <div>
          <h3 class="font-semibold mb-2">Root Folders</h3>
          <ul id="root-folders" class="space-y-1" phx-update="replace">
            <li :for={rf <- @root_folders} id={"root-folder-#{rf.id}"} class="flex justify-between items-center gap-4 border p-2 rounded">
              <code class="text-sm break-all">{rf.path}</code>
              <div class="flex items-center gap-2">
                <span :if={!rf.active} class="badge badge-neutral">inactive</span>
                <.button phx-click="delete-root-folder" phx-value-id={rf.id} class="btn-xs" variant="primary">Remove</.button>
              </div>
            </li>
          </ul>
          <.form for={@root_folder_form} id="root-folder-form" phx-submit="add-root-folder" class="mt-4 flex gap-2">
            <.input field={@root_folder_form[:path]} type="text" placeholder="/data/videos" class="flex-1" />
            <.button type="submit" class="btn-sm">Add</.button>
          </.form>
        </div>
      </div>

      <div :if={@tab == :profiles} id="profiles" class="space-y-6">
        <div>
          <h3 class="font-semibold mb-2">Existing Profiles</h3>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Name</th><th>Max Height</th><th>Bitrate</th><th>Codecs</th><th>HDR</th><th>Default</th><th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={p <- @profiles} id={"profile-#{p.id}"}>
                  <td>{p.name}</td>
                  <td>{p.max_height || "-"}</td>
                  <td>{p.max_bitrate_kbps || "-"}</td>
                  <td>{Enum.join(p.preferred_codecs, ", ")}</td>
                  <td>{p.allow_hdr && "Yes" || "No"}</td>
                  <td>{p.is_default && "✓"}</td>
                  <td><.button phx-click="delete-profile" phx-value-id={p.id} class="btn-xs" variant="primary">Delete</.button></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h3 class="font-semibold mb-2">Add Profile</h3>
          <.form for={@profile_form} id="profile-form" phx-submit="create-profile" class="grid md:grid-cols-3 gap-4">
            <.input field={@profile_form[:name]} type="text" label="Name" />
            <.input field={@profile_form[:max_height]} type="number" label="Max Height" />
            <.input field={@profile_form[:max_bitrate_kbps]} type="number" label="Max Bitrate (kbps)" />
            <.input field={@profile_form[:preferred_codecs]} type="text" label="Preferred Codecs (comma sep)" />
            <.input field={@profile_form[:allow_hdr]} type="checkbox" label="Allow HDR" />
            <.input field={@profile_form[:format_selector]} type="text" label="Format Selector (yt-dlp)" />
            <.input field={@profile_form[:is_default]} type="checkbox" label="Default" />
            <div class="md:col-span-3"><.button type="submit">Create Profile</.button></div>
          </.form>
        </div>
      </div>

      <div :if={@tab == :youtube} id="youtube" class="space-y-6">
        <.form for={@youtube_form} id="youtube-form" phx-submit="save-youtube">
          <.input field={@youtube_form[:api_key]} type="password" label="Primary API Key" />
          <.input field={@youtube_form[:region]} type="text" label="Region" />
          <.button type="submit" class="mt-2">Save YouTube Settings</.button>
        </.form>
        <p class="text-xs opacity-70">API key may be overridden by environment variable YTDARR_YOUTUBE_API_KEY.</p>
      </div>

      <div :if={@tab == :downloader} id="downloader" class="space-y-6">
        <div>
          <h3 class="font-semibold mb-2">yt-dlp Parameter Sets</h3>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr><th>Name</th><th>Format</th><th>Rate Limit</th><th>Concurrency</th><th>Default</th><th></th></tr>
              </thead>
              <tbody>
                <tr :for={s <- @param_sets} id={"param-set-#{s.id}"}>
                  <td>{s.name}</td>
                  <td>{s.format || "-"}</td>
                  <td>{s.rate_limit_kbps || "-"}</td>
                  <td>{s.concurrency || "-"}</td>
                  <td>{s.is_default && "✓"}</td>
                  <td><.button phx-click="delete-param-set" phx-value-id={s.id} class="btn-xs" variant="primary">Delete</.button></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h3 class="font-semibold mb-2">Add Param Set</h3>
          <.form for={@param_set_form} id="param-set-form" phx-submit="create-param-set" class="grid md:grid-cols-3 gap-4">
            <.input field={@param_set_form[:name]} type="text" label="Name" />
            <.input field={@param_set_form[:format]} type="text" label="Format (override)" />
            <.input field={@param_set_form[:extra_args]} type="text" label="Extra Args (space separated)" />
            <.input field={@param_set_form[:rate_limit_kbps]} type="number" label="Rate Limit (kbps)" />
            <.input field={@param_set_form[:concurrency]} type="number" label="Concurrency" />
            <.input field={@param_set_form[:is_default]} type="checkbox" label="Default" />
            <div class="md:col-span-3"><.button type="submit">Create Param Set</.button></div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
