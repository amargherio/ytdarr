defmodule YtdarrWeb.SettingsLive do
  use YtdarrWeb, :live_view

  require Logger

  import YtdarrWeb.SettingsLive.Components
  import YtdarrWeb.SettingsLive.Sections

  alias Ytdarr.{MediaPermissions, Settings}
  alias Ytdarr.Services.YouTube.QuotaTracker
  alias Ytdarr.Settings.{MediaRootFolder, QualityProfile, YtDlpParamSet}

  @categories [
    %{id: :media, label: "Media Management", icon: "hero-folder"},
    %{id: :profiles, label: "Profiles", icon: "hero-adjustments-horizontal"},
    %{id: :youtube, label: "YouTube", icon: "hero-play-circle"},
    %{id: :download, label: "Download", icon: "hero-arrow-down-tray"},
    %{id: :general, label: "General", icon: "hero-cog-6-tooth"},
    %{id: :system, label: "System", icon: "hero-server-stack"}
  ]

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: MediaPermissions.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:current_scope, nil)
     |> assign(:categories, @categories)
     |> assign(:category, category_from(params))
     |> assign(:dirty_section, nil)
     |> assign(:editor_kind, nil)
     |> assign(:editor_mode, nil)
     |> assign(:editor_record_id, nil)
     |> assign(:editor_return_focus, nil)
     |> assign(:editor_form, nil)
     |> assign(:path_check, nil)
     |> assign(:youtube_check, nil)
     |> assign(:last_path_check_at, nil)
     |> assign(:last_youtube_test_at, nil)
     |> load_data()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:category, category_from(params))
     |> close_editor()}
  end

  @impl true
  def handle_event("navigate-category", %{"category" => category}, socket) do
    {:noreply, push_patch(socket, to: ~p"/settings?category=#{category}")}
  end

  def handle_event("change-media", %{"media" => params}, socket) do
    {:noreply,
     socket
     |> assign(:media_form, to_form(params, as: :media))
     |> assign(:dirty_section, :media)}
  end

  def handle_event("change-youtube", %{"youtube" => params}, socket) do
    {:noreply,
     socket
     |> assign(:youtube_form, to_form(params, as: :youtube))
     |> assign(:dirty_section, :youtube)
     |> assign(:youtube_check, nil)}
  end

  def handle_event("change-general", %{"general" => params}, socket) do
    {:noreply,
     socket
     |> assign(:general_form, to_form(params, as: :general))
     |> assign(:dirty_section, :general)}
  end

  def handle_event("discard-section-changes", _params, socket) do
    {:noreply, socket |> assign(:dirty_section, nil) |> load_data()}
  end

  def handle_event("save-media", %{"media" => params}, socket) do
    with {:ok, policy} <- MediaPermissions.build_policy(params),
         {:ok, _settings} <-
           Settings.save_settings([
             {"media.file_naming_template", params["file_naming_template"]},
             {"media.move_strategy", params["move_strategy"]},
             {"media.clean_orphans", truthy?(params["clean_orphans"])},
             {"media.owner_group", policy.owner_group},
             {"media.file_mode", policy.file_mode},
             {"media.directory_mode", policy.directory_mode}
           ]) do
      {:noreply,
       socket
       |> put_flash(:info, "Media settings saved. New filesystem writes use these permissions.")
       |> assign(:dirty_section, nil)
       |> load_data()}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, media_settings_error(reason))}
    end
  end

  def handle_event("apply-media-permissions", _params, socket) do
    case MediaPermissions.enqueue_existing_media() do
      {:ok, job} ->
        {:noreply,
         socket
         |> assign(:media_permissions_job, job)
         |> assign(:media_permissions_active?, true)
         |> put_flash(:info, "Media permission update queued.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, MediaPermissions.error_message(reason))}
    end
  end

  def handle_event("save-youtube", %{"youtube" => params}, socket) do
    with :ok <- ensure_region(params["region"]),
         {:ok, _settings} <- Settings.save_settings(youtube_settings(params)) do
      {:noreply,
       socket
       |> put_flash(:info, "YouTube settings saved.")
       |> assign(:dirty_section, nil)
       |> assign(:youtube_check, nil)
       |> load_data()}
    else
      {:error, :region_required} ->
        {:noreply, put_flash(socket, :error, "Enter a two-letter YouTube region code.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, operation_error("save YouTube settings", reason))}
    end
  end

  def handle_event("save-general", %{"general" => params}, socket) do
    case parse_positive_integer(params["sync_interval_minutes"]) do
      {:ok, minutes} ->
        case Settings.save_settings([{"sync_interval_minutes", minutes}]) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Sync interval saved. It applies when the next batch sync schedules its successor."
             )
             |> assign(:dirty_section, nil)
             |> load_data()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, operation_error("save sync interval", reason))}
        end

      {:error, :not_positive_integer} ->
        {:noreply, put_flash(socket, :error, "Sync interval must be a positive whole number.")}
    end
  end

  def handle_event("clear-youtube-api-key", _params, socket) do
    if youtube_key_from_environment?() do
      {:noreply,
       put_flash(
         socket,
         :error,
         "The API key is managed by YTDARR_YOUTUBE_API_KEY and cannot be cleared here."
       )}
    else
      case Settings.delete_setting("youtube.primary_api_key") do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Browser-managed YouTube API key cleared.")
           |> assign(:youtube_check, nil)
           |> load_data()}

        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Browser-managed YouTube API key cleared.")
           |> assign(:youtube_check, nil)
           |> load_data()}

        {:error, :not_found} ->
          {:noreply, put_flash(socket, :error, "No browser-managed API key is stored.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, operation_error("clear the API key", reason))}
      end
    end
  end

  def handle_event("test-youtube-credentials", _params, socket) do
    if rate_limited?(socket.assigns.last_youtube_test_at, 5_000) do
      {:noreply,
       assign(socket, :youtube_check, {:error, "Wait a few seconds before testing again."})}
    else
      pending_key = socket.assigns.youtube_form[:api_key].value

      api_key =
        if present?(pending_key),
          do: pending_key,
          else: Settings.get_setting_value("youtube.primary_api_key")

      result =
        case Settings.test_youtube_credential(api_key, youtube_credential_test_options()) do
          {:ok, _details} -> {:ok, "Credentials are valid and the YouTube API responded."}
          {:error, reason} -> {:error, youtube_test_error(reason)}
        end

      {:noreply,
       socket
       |> assign(:last_youtube_test_at, monotonic_milliseconds())
       |> assign(:youtube_check, result)}
    end
  end

  def handle_event("open-editor", %{"kind" => kind} = params, socket) do
    with {:ok, editor_kind} <- parse_editor_kind(kind),
         {:ok, record} <- fetch_editor_record(editor_kind, params["id"]) do
      {:noreply,
       socket
       |> assign(:editor_kind, editor_kind)
       |> assign(:editor_mode, if(record, do: :edit, else: :create))
       |> assign(:editor_record_id, record && record.id)
       |> assign(:editor_return_focus, editor_return_focus(editor_kind, params["id"]))
       |> assign(:editor_form, build_editor_form(editor_kind, record))
       |> assign(:path_check, nil)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, operation_error("open the editor", reason))}
    end
  end

  def handle_event("close-editor", _params, socket) do
    {:noreply, close_editor(socket)}
  end

  def handle_event("validate-editor", params, socket) do
    editor_params =
      params
      |> Map.get(editor_param_key(socket.assigns.editor_kind), %{})
      |> normalize_editor_params(socket.assigns.editor_kind, socket.assigns.editor_mode)

    form =
      socket.assigns.editor_form.source
      |> AshPhoenix.Form.validate(editor_params)
      |> to_form()

    {:noreply, socket |> assign(:editor_form, form) |> assign(:path_check, nil)}
  end

  def handle_event("save-editor", params, socket) do
    editor_params =
      params
      |> Map.get(editor_param_key(socket.assigns.editor_kind), %{})
      |> normalize_editor_params(socket.assigns.editor_kind, socket.assigns.editor_mode)

    case AshPhoenix.Form.submit(socket.assigns.editor_form.source, params: editor_params) do
      {:ok, _record} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           editor_success_message(socket.assigns.editor_kind, socket.assigns.editor_mode)
         )
         |> close_editor()
         |> load_data()}

      {:error, form} ->
        {:noreply, assign(socket, :editor_form, to_form(form))}
    end
  end

  def handle_event(
        "validate-root-path",
        _params,
        %{assigns: %{editor_kind: :root_folder}} = socket
      ) do
    if rate_limited?(socket.assigns.last_path_check_at, 1_000) do
      {:noreply, assign(socket, :path_check, {:error, "Wait a moment before checking again."})}
    else
      path = socket.assigns.editor_form[:path].value

      result =
        case Settings.validate_media_root_path(path) do
          :ok -> {:ok, "Path exists, is a directory, and is writable."}
          {:error, reason} -> {:error, path_error(reason)}
        end

      {:noreply,
       socket
       |> assign(:last_path_check_at, monotonic_milliseconds())
       |> assign(:path_check, result)}
    end
  end

  def handle_event("validate-root-path", _params, socket), do: {:noreply, socket}

  def handle_event("toggle-root-folder", %{"id" => id}, socket) do
    with {:ok, folder} when not is_nil(folder) <- Settings.get_media_root_folder(id),
         result <-
           if(folder.active,
             do: Settings.deactivate_media_root_folder(folder),
             else: Settings.activate_media_root_folder(folder)
           ),
         {:ok, _} <- normalize_action_result(result) do
      message = if folder.active, do: "Root folder deactivated.", else: "Root folder activated."
      {:noreply, socket |> put_flash(:info, message) |> load_data()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, operation_error("change the root folder", reason))}

      _ ->
        {:noreply, put_flash(socket, :error, "Root folder not found.")}
    end
  end

  def handle_event("set-default-profile", %{"id" => id}, socket) do
    with {:ok, profile} when not is_nil(profile) <- Settings.get_quality_profile(id),
         {:ok, _} <- Settings.set_default_quality_profile(profile) do
      {:noreply,
       socket |> put_flash(:info, "#{profile.name} is now the default profile.") |> load_data()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, operation_error("set the default profile", reason))}

      _ ->
        {:noreply, put_flash(socket, :error, "Quality profile not found.")}
    end
  end

  def handle_event("set-default-param-set", %{"id" => id}, socket) do
    with {:ok, param_set} when not is_nil(param_set) <- Settings.get_yt_dlp_param_set(id),
         {:ok, _} <- Settings.set_default_yt_dlp_param_set(param_set) do
      {:noreply,
       socket
       |> put_flash(:info, "#{param_set.name} is now the default parameter set.")
       |> load_data()}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, operation_error("set the default parameter set", reason))}

      _ ->
        {:noreply, put_flash(socket, :error, "Parameter set not found.")}
    end
  end

  def handle_event("delete-resource", %{"kind" => kind, "id" => id}, socket) do
    with {:ok, editor_kind} <- parse_editor_kind(kind),
         {:ok, record} when not is_nil(record) <- fetch_editor_record(editor_kind, id),
         {:ok, _} <- destroy_record(editor_kind, record) do
      {:noreply,
       socket
       |> put_flash(:info, resource_deleted_message(editor_kind))
       |> close_editor()
       |> load_data()}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, operation_error("delete this setting", reason))}

      _ ->
        {:noreply, put_flash(socket, :error, "The requested setting was not found.")}
    end
  end

  @impl true
  def handle_info({event, _job_id, _metadata}, socket)
      when event in [:media_permissions_completed, :media_permissions_failed] do
    {:noreply,
     socket
     |> assign(:media_permissions_job, MediaPermissions.latest_job())
     |> assign(:media_permissions_active?, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} nav={:settings} current_scope={@current_scope}>
      <div id="settings-page" class="mx-auto w-full max-w-[90rem]">
        <div class="mb-6">
          <h1 class="text-2xl font-bold tracking-tight text-base-content">Settings</h1>
          <p class="mt-1 max-w-3xl text-sm leading-6 text-base-content/60">
            Configure Ytdarr, verify external dependencies, and see exactly when each value takes effect.
          </p>
        </div>

        <div class="grid gap-6 lg:grid-cols-[13rem_minmax(0,1fr)] xl:gap-8">
          <aside class="min-w-0 lg:border-r lg:border-base-300 lg:pr-5">
            <.category_navigation active={@category} items={@categories} />
          </aside>

          <section id={"settings-section-#{@category}"} class="min-w-0">
            <.media_section :if={@category == :media} {assigns} />
            <.profiles_section :if={@category == :profiles} {assigns} />
            <.youtube_section :if={@category == :youtube} {assigns} />
            <.download_section :if={@category == :download} {assigns} />
            <.general_section :if={@category == :general} {assigns} />
            <.system_section :if={@category == :system} {assigns} />
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp load_data(socket) do
    cfg = Settings.effective_config()
    root_folders = Enum.sort_by(cfg.media.root_folders, &{!&1.active, &1.path})
    media_permissions_job = MediaPermissions.latest_job()

    root_folder_checks =
      Map.new(root_folders, &{&1.id, Settings.validate_media_root_path(&1.path)})

    setting_states =
      Map.new(
        ~w(
          media.file_naming_template
          media.move_strategy
          media.clean_orphans
          media.owner_group
          media.file_mode
          media.directory_mode
          youtube.primary_api_key
          youtube.region
          sync_interval_minutes
        ),
        &{&1, Settings.setting_state(&1)}
      )

    media_form =
      to_form(
        %{
          "file_naming_template" => setting_states["media.file_naming_template"].value,
          "move_strategy" => setting_states["media.move_strategy"].value,
          "clean_orphans" => setting_states["media.clean_orphans"].value,
          "owner_group" => setting_states["media.owner_group"].value,
          "file_mode" => setting_states["media.file_mode"].value,
          "directory_mode" => setting_states["media.directory_mode"].value
        },
        as: :media
      )

    youtube_key_state = setting_states["youtube.primary_api_key"]

    youtube_form =
      to_form(
        %{
          "api_key" => "",
          "region" => setting_states["youtube.region"].value
        },
        as: :youtube
      )

    general_form =
      to_form(
        %{
          "sync_interval_minutes" => setting_states["sync_interval_minutes"].value
        },
        as: :general
      )

    socket
    |> assign(:media_form, media_form)
    |> assign(:youtube_form, youtube_form)
    |> assign(:general_form, general_form)
    |> assign(:profiles, Enum.sort_by(cfg.profiles, &{!&1.is_default, String.downcase(&1.name)}))
    |> assign(
      :param_sets,
      Enum.sort_by(cfg.downloader.param_sets, &{!&1.is_default, String.downcase(&1.name)})
    )
    |> assign(:root_folders, root_folders)
    |> assign(:root_folder_checks, root_folder_checks)
    |> assign(:last_active_root_id, last_active_root_id(root_folders))
    |> assign(:media_permissions_job, media_permissions_job)
    |> assign(:media_permissions_active?, media_permissions_active?(media_permissions_job))
    |> assign(:setting_effects, setting_effects(setting_states))
    |> assign(
      :move_strategy_options,
      Enum.map(
        setting_states["media.move_strategy"].metadata.allowed_values,
        &{String.capitalize(&1), &1}
      )
    )
    |> assign(:youtube_key_source, youtube_key_state.source)
    |> assign(:youtube_key_configured?, youtube_key_state.configured?)
    |> assign(:quota_usage, quota_usage())
    |> assign(:system_rows, system_rows(root_folders, root_folder_checks))
  end

  defp category_from(%{"category" => category}), do: parse_category(category)
  defp category_from(%{"tab" => "downloader"}), do: :download
  defp category_from(%{"tab" => tab}), do: parse_category(tab)
  defp category_from(_params), do: :media

  defp parse_category(category)
       when category in ~w(media profiles youtube download general system),
       do: String.to_existing_atom(category)

  defp parse_category("downloader"), do: :download
  defp parse_category(_category), do: :media

  defp close_editor(socket) do
    socket
    |> assign(:editor_kind, nil)
    |> assign(:editor_mode, nil)
    |> assign(:editor_record_id, nil)
    |> assign(:editor_return_focus, nil)
    |> assign(:editor_form, nil)
    |> assign(:path_check, nil)
  end

  defp parse_editor_kind("root_folder"), do: {:ok, :root_folder}
  defp parse_editor_kind("profile"), do: {:ok, :profile}
  defp parse_editor_kind("param_set"), do: {:ok, :param_set}
  defp parse_editor_kind(_kind), do: {:error, :invalid_editor}

  defp editor_return_focus(:root_folder, nil), do: "#add-root-folder"
  defp editor_return_focus(:profile, nil), do: "#add-quality-profile"
  defp editor_return_focus(:param_set, nil), do: "#add-param-set"
  defp editor_return_focus(:root_folder, id), do: "#edit-root-folder-#{id}"
  defp editor_return_focus(:profile, id), do: "#edit-profile-#{id}"
  defp editor_return_focus(:param_set, id), do: "#edit-param-set-#{id}"

  defp fetch_editor_record(_kind, nil), do: {:ok, nil}
  defp fetch_editor_record(:root_folder, id), do: Settings.get_media_root_folder(id)
  defp fetch_editor_record(:profile, id), do: Settings.get_quality_profile(id)
  defp fetch_editor_record(:param_set, id), do: Settings.get_yt_dlp_param_set(id)

  defp build_editor_form(:root_folder, nil) do
    AshPhoenix.Form.for_create(MediaRootFolder, :create,
      domain: Settings,
      as: "root_folder"
    )
    |> AshPhoenix.Form.validate(%{"active" => true, "purpose" => "videos"})
    |> to_form()
  end

  defp build_editor_form(:root_folder, folder) do
    AshPhoenix.Form.for_update(folder, :update, domain: Settings, as: "root_folder")
    |> to_form()
  end

  defp build_editor_form(:profile, nil) do
    AshPhoenix.Form.for_create(QualityProfile, :create, domain: Settings, as: "profile")
    |> AshPhoenix.Form.validate(%{"allow_hdr" => true})
    |> to_form()
  end

  defp build_editor_form(:profile, profile) do
    AshPhoenix.Form.for_update(profile, :update,
      domain: Settings,
      as: "profile",
      params: %{"preferred_codecs" => Enum.join(profile.preferred_codecs || [], ", ")}
    )
    |> to_form()
  end

  defp build_editor_form(:param_set, nil) do
    AshPhoenix.Form.for_create(YtDlpParamSet, :create, domain: Settings, as: "param_set")
    |> to_form()
  end

  defp build_editor_form(:param_set, param_set) do
    AshPhoenix.Form.for_update(param_set, :update, domain: Settings, as: "param_set")
    |> to_form()
  end

  defp editor_param_key(:root_folder), do: "root_folder"
  defp editor_param_key(:profile), do: "profile"
  defp editor_param_key(:param_set), do: "param_set"

  defp normalize_editor_params(params, :profile, mode) do
    codecs =
      params
      |> Map.get("preferred_codecs", "")
      |> to_string()
      |> String.split([",", "\n"], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    params
    |> Map.put("preferred_codecs", codecs)
    |> maybe_drop_default_flag(mode)
  end

  defp normalize_editor_params(params, :param_set, mode),
    do: maybe_drop_default_flag(params, mode)

  defp normalize_editor_params(params, _kind, _mode), do: params

  defp maybe_drop_default_flag(params, :edit), do: Map.delete(params, "is_default")
  defp maybe_drop_default_flag(params, :create), do: params

  defp editor_success_message(:root_folder, :create), do: "Root folder added."
  defp editor_success_message(:root_folder, :edit), do: "Root folder updated."
  defp editor_success_message(:profile, :create), do: "Quality profile created."
  defp editor_success_message(:profile, :edit), do: "Quality profile updated."
  defp editor_success_message(:param_set, :create), do: "Parameter set created."
  defp editor_success_message(:param_set, :edit), do: "Parameter set updated."

  defp resource_deleted_message(:root_folder), do: "Root folder deleted."
  defp resource_deleted_message(:profile), do: "Quality profile deleted."
  defp resource_deleted_message(:param_set), do: "Parameter set deleted."

  defp destroy_record(:root_folder, folder),
    do: normalize_action_result(Settings.destroy_media_root_folder(folder))

  defp destroy_record(:profile, profile),
    do: normalize_action_result(Settings.destroy_quality_profile(profile))

  defp destroy_record(:param_set, param_set),
    do: normalize_action_result(Settings.destroy_yt_dlp_param_set(param_set))

  defp normalize_action_result(:ok), do: {:ok, :ok}
  defp normalize_action_result({:ok, result}), do: {:ok, result}
  defp normalize_action_result({:error, reason}), do: {:error, reason}

  defp youtube_settings(params) do
    settings = [{"youtube.region", params["region"] |> String.trim() |> String.upcase()}]

    if present?(params["api_key"]) do
      [{"youtube.primary_api_key", String.trim(params["api_key"])} | settings]
    else
      settings
    end
  end

  defp ensure_region(value) when is_binary(value) do
    if String.match?(String.trim(value), ~r/^[A-Za-z]{2}$/) do
      :ok
    else
      {:error, :region_required}
    end
  end

  defp ensure_region(_value), do: {:error, :region_required}

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, :not_positive_integer}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :not_positive_integer}

  defp truthy?(value), do: value in [true, "true", "on", "1", 1]
  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp youtube_key_from_environment? do
    present?(System.get_env("YTDARR_YOUTUBE_API_KEY"))
  end

  defp quota_usage do
    if Process.whereis(QuotaTracker), do: QuotaTracker.get_usage(), else: nil
  end

  defp youtube_credential_test_options do
    case Application.get_env(:ytdarr, __MODULE__, [])[:credential_test_client] do
      nil -> []
      client -> [client: client]
    end
  end

  defp last_active_root_id(root_folders) do
    case Enum.filter(root_folders, & &1.active) do
      [folder] -> folder.id
      _ -> nil
    end
  end

  defp system_rows(root_folders, root_folder_checks) do
    endpoint_config = Application.get_env(:ytdarr, YtdarrWeb.Endpoint, [])
    repo_config = Application.get_env(:ytdarr, Ytdarr.Repo, [])
    oban_config = Application.get_env(:ytdarr, Oban, [])
    url_config = Keyword.get(endpoint_config, :url, [])
    http_config = Keyword.get(endpoint_config, :http, [])

    [
      %{
        id: "system-version",
        label: "Ytdarr version",
        value: to_string(Application.spec(:ytdarr, :vsn) || "unknown"),
        description: "Running application release."
      },
      %{
        id: "system-environment",
        label: "Runtime environment",
        value: System.get_env("MIX_ENV") || "runtime",
        description: "Build and runtime environment."
      },
      %{
        id: "system-public-host",
        label: "Public host",
        value: to_string(Keyword.get(url_config, :host, "localhost")),
        description: "Configured by PHX_HOST.",
        status: :restart_required
      },
      %{
        id: "system-http-port",
        label: "HTTP port",
        value: to_string(Keyword.get(http_config, :port, System.get_env("PORT") || "4000")),
        description: "Configured by PORT.",
        status: :restart_required
      },
      %{
        id: "system-database-path",
        label: "Database path",
        value: to_string(Keyword.get(repo_config, :database, "environment default")),
        description: "Configured by DATABASE_PATH.",
        status: :restart_required
      },
      %{
        id: "system-database-pool",
        label: "Database pool",
        value: to_string(Keyword.get(repo_config, :pool_size, 10)),
        description: "Configured by POOL_SIZE.",
        status: :restart_required
      },
      %{
        id: "system-oban-queues",
        label: "Oban queues",
        value: format_queues(Keyword.get(oban_config, :queues, [])),
        description: "Worker concurrency is deployment-managed.",
        status: :restart_required
      },
      %{
        id: "system-ytdlp-executable",
        label: "yt-dlp executable",
        value: System.find_executable("yt-dlp") || "Not found",
        description: "Required for downloads."
      },
      %{
        id: "system-database-connectivity",
        label: "Database connectivity",
        value: database_status(),
        description: "Live repository health check."
      },
      %{
        id: "system-root-folder-health",
        label: "Root folder health",
        value: root_folder_health(root_folders, root_folder_checks),
        description: "Checks configured active folders on this host."
      },
      %{
        id: "system-secret-key-base",
        label: "Secret key base",
        value: "configured",
        description: "Configured by SECRET_KEY_BASE.",
        sensitive: true,
        status: :restart_required
      },
      %{
        id: "system-token-signing-secret",
        label: "Token signing secret",
        value: "configured",
        description: "Configured by TOKEN_SIGNING_SECRET.",
        sensitive: true,
        status: :restart_required
      }
    ]
  end

  defp format_queues(queues) when is_list(queues) do
    queues
    |> Enum.map_join(", ", fn {queue, concurrency} -> "#{queue}: #{concurrency}" end)
    |> case do
      "" -> "Not configured"
      value -> value
    end
  end

  defp format_queues(_queues), do: "Runtime managed"

  defp database_status do
    case Ytdarr.Repo.query("SELECT 1") do
      {:ok, _result} -> "Connected"
      {:error, _reason} -> "Unavailable"
    end
  end

  defp root_folder_health(root_folders, root_folder_checks) do
    active_folders = Enum.filter(root_folders, & &1.active)
    healthy = Enum.count(active_folders, &(root_folder_checks[&1.id] == :ok))
    "#{healthy}/#{length(active_folders)} active folders healthy"
  end

  defp path_error(:not_absolute), do: "Use an absolute path, such as /data/videos."
  defp path_error(:not_found), do: "The path does not exist on the Ytdarr host."
  defp path_error(:not_directory), do: "The path exists but is not a directory."
  defp path_error(:not_writable), do: "Ytdarr cannot write to this directory."

  defp media_settings_error({tag, _details} = reason)
       when tag in [
              :invalid_group,
              :group_not_found,
              :group_not_available,
              :group_lookup_unavailable,
              :invalid_mode
            ],
       do: MediaPermissions.error_message(reason)

  defp media_settings_error({:invalid_mode, _field, _value} = reason),
    do: MediaPermissions.error_message(reason)

  defp media_settings_error(reason), do: operation_error("save media settings", reason)

  defp media_permissions_active?(%{state: state})
       when state in ["available", "scheduled", "executing", "retryable", "suspended"],
       do: true

  defp media_permissions_active?(_job), do: false

  defp youtube_test_error(:empty_key), do: "Configure an API key before testing."

  defp youtube_test_error(:invalid_key),
    do: "YouTube rejected this API key. Check the key and API restrictions."

  defp youtube_test_error(:quota_exceeded),
    do: "The YouTube project has exhausted its API quota for the day."

  defp youtube_test_error({:http_error, status, message}),
    do: youtube_http_error(status, message)

  defp youtube_test_error({:network, reason}) do
    Logger.warning(
      "[SettingsLive] YouTube credential test network failure: #{error_kind(reason)}"
    )

    "Could not reach YouTube. Check network access and try again."
  end

  defp setting_effects(setting_states) do
    Map.new(setting_states, fn {key, state} ->
      effect =
        case state.metadata.effect_status do
          :runtime -> :immediate
          :next_schedule -> :next_schedule
          :stored_only -> :stored_only
        end

      {key, effect}
    end)
  end

  defp operation_error(action, reason) do
    Logger.warning("[SettingsLive] #{action} failed: #{error_kind(reason)}")
    "Could not #{action}. Check the values and try again."
  end

  defp youtube_http_error(status, _message) do
    Logger.warning("[SettingsLive] YouTube credential test returned HTTP #{status}")
    "YouTube returned HTTP #{status}. Check API access and try again."
  end

  defp error_kind(%{__struct__: module}), do: inspect(module)
  defp error_kind({tag, _details}) when is_atom(tag), do: Atom.to_string(tag)
  defp error_kind(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_kind(_reason), do: "unknown_error"

  defp rate_limited?(nil, _interval), do: false

  defp rate_limited?(last_at, interval) do
    monotonic_milliseconds() - last_at < interval
  end

  defp monotonic_milliseconds, do: System.monotonic_time(:millisecond)
end
