defmodule YtdarrWeb.SettingsLive.Sections do
  @moduledoc """
  Function components that render each settings category section and the
  inline resource editor panel.  All presentational logic lives here;
  event handling and state remain in `YtdarrWeb.SettingsLive`.
  """
  use YtdarrWeb, :html

  import YtdarrWeb.SettingsLive.Components

  # ---------------------------------------------------------------------------
  # Section components
  # ---------------------------------------------------------------------------

  def media_section(assigns) do
    ~H"""
    <.section_header
      title="Media Management"
      description="Control media organization and the filesystem roots used when Ytdarr creates new channel paths."
      icon="hero-folder"
    />

    <.form
      for={@media_form}
      id="media-form"
      phx-change="change-media"
      phx-submit="save-media"
      class="mt-2"
    >
      <.setting_row
        id="media-file-naming-template"
        label="File naming template"
        description="Stored for a future naming pipeline. Current downloads continue to use Ytdarr's built-in series and episode naming."
        effect={@setting_effects["media.file_naming_template"]}
      >
        <:control>
          <.input
            field={@media_form[:file_naming_template]}
            type="text"
            label="Template"
            autocomplete="off"
          />
        </:control>
      </.setting_row>

      <.setting_row
        id="media-move-strategy"
        label="File placement strategy"
        description="Choose the intended placement behavior. Current downloads write directly to the destination path."
        effect={@setting_effects["media.move_strategy"]}
      >
        <:control>
          <.input
            field={@media_form[:move_strategy]}
            type="select"
            label="Strategy"
            options={@move_strategy_options}
          />
        </:control>
      </.setting_row>

      <.setting_row
        id="media-clean-orphans"
        label="Clean orphaned files"
        description="Records the desired cleanup policy. Automated orphan cleanup is not active yet."
        effect={@setting_effects["media.clean_orphans"]}
      >
        <:control>
          <.input
            field={@media_form[:clean_orphans]}
            type="checkbox"
            label="Enable automatic cleanup when support is available"
          />
        </:control>
      </.setting_row>
    </.form>

    <.save_bar
      :if={@dirty_section == :media}
      section="Media Management"
      form_id="media-form"
    />

    <div class="mt-10">
      <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 class="text-base font-semibold text-base-content">Root folders</h2>
          <p class="mt-1 max-w-2xl text-sm leading-6 text-base-content/60">
            The first active folder supplies the base path for newly added channels. Existing files are not moved.
          </p>
        </div>
        <button
          id="add-root-folder"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="open-editor"
          phx-value-kind="root_folder"
        >
          <.icon name="hero-plus" class="size-4" /> Add root folder
        </button>
      </div>

      <div class={["grid gap-5", @editor_kind == :root_folder && "lg:grid-cols-[minmax(0,1fr)_24rem]"]}>
        <div class={["min-w-0", @editor_kind == :root_folder && "max-lg:hidden"]}>
          <.empty_state
            :if={@root_folders == []}
            id="root-folders-empty"
            title="No root folders configured"
            description="Add a writable absolute path before downloading media. Ytdarr otherwise falls back to /downloads."
            icon="hero-folder-plus"
          >
            <:action>
              <button
                id="add-root-folder-empty"
                type="button"
                class="btn btn-primary btn-sm"
                phx-click="open-editor"
                phx-value-kind="root_folder"
              >
                Add root folder
              </button>
            </:action>
          </.empty_state>

          <div
            :if={@root_folders != []}
            id="root-folders"
            class="divide-y divide-base-300 border-y border-base-300"
          >
            <div
              :for={folder <- @root_folders}
              id={"root-folder-#{folder.id}"}
              class="grid gap-3 py-4 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"
            >
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <code class="break-all text-sm font-medium text-base-content">{folder.path}</code>
                  <span class={[
                    "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium",
                    if(folder.active,
                      do: "bg-success/15 text-success",
                      else: "bg-base-300 text-base-content/55"
                    )
                  ]}>
                    <.icon
                      name={if(folder.active, do: "hero-check-circle", else: "hero-pause-circle")}
                      class="size-3.5"
                    />
                    {if(folder.active, do: "Active", else: "Inactive")}
                  </span>
                  <.effect_badge status={:new_items} />
                  <.root_folder_health_badge result={@root_folder_checks[folder.id]} />
                </div>
                <p class="mt-1 text-xs text-base-content/50">Purpose: {folder.purpose}</p>
              </div>
              <div class="flex flex-wrap items-center gap-1 sm:justify-end">
                <button
                  id={"edit-root-folder-#{folder.id}"}
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="open-editor"
                  phx-value-kind="root_folder"
                  phx-value-id={folder.id}
                >
                  <.icon name="hero-pencil-square" class="size-4" /> Edit
                </button>
                <button
                  id={"toggle-root-folder-#{folder.id}"}
                  type="button"
                  class="btn btn-ghost btn-sm"
                  phx-click="toggle-root-folder"
                  phx-value-id={folder.id}
                  disabled={folder.id == @last_active_root_id}
                  title={
                    folder.id == @last_active_root_id &&
                      "Activate another root folder before deactivating this one."
                  }
                >
                  {if(folder.active, do: "Deactivate", else: "Activate")}
                </button>
                <button
                  id={"delete-root-folder-#{folder.id}"}
                  type="button"
                  class="btn btn-ghost btn-sm text-error hover:bg-error/10"
                  phx-click="delete-resource"
                  phx-value-kind="root_folder"
                  phx-value-id={folder.id}
                  disabled={folder.id == @last_active_root_id}
                  title={
                    folder.id == @last_active_root_id &&
                      "Activate another root folder before deleting this one."
                  }
                  data-confirm={"Delete root folder #{folder.path}? Existing files will not be removed."}
                >
                  <.icon name="hero-trash" class="size-4" />
                  <span class="sr-only">Delete {folder.path}</span>
                </button>
              </div>
            </div>
          </div>
        </div>

        <.resource_editor
          :if={@editor_kind == :root_folder}
          kind={@editor_kind}
          mode={@editor_mode}
          form={@editor_form}
          path_check={@path_check}
          editor_return_focus={@editor_return_focus}
          protected={not is_nil(@editor_record_id) and @editor_record_id == @last_active_root_id}
        />
      </div>
    </div>
    """
  end

  def profiles_section(assigns) do
    ~H"""
    <.section_header
      title="Profiles"
      description="Define reusable quality preferences. Profiles are fully manageable here but are not yet selected by the downloader."
      icon="hero-adjustments-horizontal"
    >
      <:actions>
        <button
          id="add-quality-profile"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="open-editor"
          phx-value-kind="profile"
        >
          <.icon name="hero-plus" class="size-4" /> Add profile
        </button>
      </:actions>
    </.section_header>

    <div class={["mt-6 grid gap-5", @editor_kind == :profile && "lg:grid-cols-[minmax(0,1fr)_24rem]"]}>
      <div class={["min-w-0", @editor_kind == :profile && "max-lg:hidden"]}>
        <.empty_state
          :if={@profiles == []}
          id="profiles-empty"
          title="No quality profiles"
          description="Create a profile to record quality, codec, HDR, and format preferences."
          icon="hero-adjustments-horizontal"
        >
          <:action>
            <button
              id="add-quality-profile-empty"
              type="button"
              class="btn btn-primary btn-sm"
              phx-click="open-editor"
              phx-value-kind="profile"
            >
              Add profile
            </button>
          </:action>
        </.empty_state>

        <div
          :if={@profiles != []}
          id="quality-profiles"
          class="divide-y divide-base-300 border-y border-base-300"
        >
          <div
            :for={profile <- @profiles}
            id={"profile-#{profile.id}"}
            class="grid gap-3 py-4 md:grid-cols-[minmax(10rem,1fr)_minmax(0,1.5fr)_auto] md:items-center"
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <h2 class="font-semibold text-base-content">{profile.name}</h2>
                <span
                  :if={profile.is_default}
                  class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
                >
                  <.icon name="hero-check-badge" class="size-3.5" /> Default
                </span>
                <.effect_badge status={:stored_only} />
              </div>
            </div>
            <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-base-content/60 sm:grid-cols-4">
              <div>
                <dt class="text-base-content/40">Height</dt>
                <dd>{profile.max_height || "Any"}</dd>
              </div>
              <div>
                <dt class="text-base-content/40">Bitrate</dt>
                <dd>{profile.max_bitrate_kbps || "Any"}</dd>
              </div>
              <div>
                <dt class="text-base-content/40">HDR</dt>
                <dd>{if(profile.allow_hdr, do: "Allowed", else: "Off")}</dd>
              </div>
              <div class="min-w-0">
                <dt class="text-base-content/40">Codecs</dt>
                <dd class="truncate">{codec_summary(profile.preferred_codecs)}</dd>
              </div>
            </dl>
            <div class="flex flex-wrap items-center gap-1 md:justify-end">
              <button
                :if={!profile.is_default}
                id={"default-profile-#{profile.id}"}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="set-default-profile"
                phx-value-id={profile.id}
              >
                Set default
              </button>
              <button
                id={"edit-profile-#{profile.id}"}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="open-editor"
                phx-value-kind="profile"
                phx-value-id={profile.id}
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </button>
              <button
                id={"delete-profile-#{profile.id}"}
                type="button"
                class="btn btn-ghost btn-sm text-error hover:bg-error/10"
                phx-click="delete-resource"
                phx-value-kind="profile"
                phx-value-id={profile.id}
                disabled={profile.is_default}
                title={
                  profile.is_default &&
                    "Set another quality profile as default before deleting this one."
                }
                data-confirm={"Delete quality profile #{profile.name}? This cannot be undone."}
              >
                <.icon name="hero-trash" class="size-4" />
                <span class="sr-only">Delete {profile.name}</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <.resource_editor
        :if={@editor_kind == :profile}
        kind={@editor_kind}
        mode={@editor_mode}
        form={@editor_form}
        path_check={@path_check}
        editor_return_focus={@editor_return_focus}
        protected={false}
      />
    </div>
    """
  end

  def youtube_section(assigns) do
    ~H"""
    <.section_header
      title="YouTube"
      description="Manage YouTube Data API credentials, inspect quota state, and verify connectivity without exposing the stored key."
      icon="hero-play-circle"
    />

    <.form
      for={@youtube_form}
      id="youtube-form"
      phx-change="change-youtube"
      phx-submit="save-youtube"
      class="mt-2"
    >
      <.setting_row
        id="youtube-api-key"
        label="API key"
        description={youtube_key_description(@youtube_key_source)}
        effect={
          if(@youtube_key_source == :environment,
            do: :environment,
            else: @setting_effects["youtube.primary_api_key"]
          )
        }
      >
        <:control>
          <.input
            field={@youtube_form[:api_key]}
            type="password"
            label="Replace API key"
            placeholder={if(@youtube_key_configured?, do: "Configured", else: "Enter API key")}
            autocomplete="new-password"
            disabled={@youtube_key_source == :environment}
          />
          <div class="mt-2 flex flex-wrap items-center gap-2">
            <button
              id="test-youtube-credentials"
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="test-youtube-credentials"
              phx-disable-with="Testing..."
            >
              <.icon name="hero-signal" class="size-4" /> Test credentials
            </button>
            <button
              :if={@youtube_key_source == :database}
              id="clear-youtube-api-key"
              type="button"
              class="btn btn-ghost btn-sm text-error hover:bg-error/10"
              phx-click="clear-youtube-api-key"
              data-confirm="Clear the browser-managed YouTube API key? YouTube features will stop working until another key is configured."
            >
              Clear stored key
            </button>
          </div>
          <.diagnostic_result
            :if={@youtube_check}
            id="youtube-credential-result"
            result={@youtube_check}
          />
        </:control>
      </.setting_row>

      <.setting_row
        id="youtube-region"
        label="Region"
        description="Records the intended two-letter ISO region code. Current YouTube requests do not use this value yet."
        effect={@setting_effects["youtube.region"]}
      >
        <:control>
          <.input
            field={@youtube_form[:region]}
            type="text"
            label="Region code"
            maxlength="2"
            placeholder="US"
            autocomplete="country"
          />
        </:control>
      </.setting_row>
    </.form>

    <.save_bar
      :if={@dirty_section == :youtube}
      section="YouTube"
      form_id="youtube-form"
    />

    <div id="youtube-quota-status" class="mt-8 border-y border-base-300 py-5">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 class="text-sm font-semibold text-base-content">Daily API quota</h2>
          <p class="mt-1 text-sm text-base-content/60">
            Ytdarr tracks estimated YouTube Data API usage to avoid unexpected exhaustion.
          </p>
        </div>
        <div :if={@quota_usage} class="flex items-center gap-5 text-sm">
          <div>
            <span class="block text-xs text-base-content/45">Used</span>
            <strong>{@quota_usage.used}</strong>
          </div>
          <div>
            <span class="block text-xs text-base-content/45">Remaining</span>
            <strong>{@quota_usage.remaining}</strong>
          </div>
        </div>
        <span :if={!@quota_usage} class="text-sm text-base-content/50">Quota tracker unavailable</span>
      </div>
    </div>
    """
  end

  def download_section(assigns) do
    ~H"""
    <.section_header
      title="Download"
      description="Manage yt-dlp parameter sets. Format and extra arguments apply to new jobs; rate and concurrency values are stored for future support."
      icon="hero-arrow-down-tray"
    >
      <:actions>
        <button
          id="add-param-set"
          type="button"
          class="btn btn-primary btn-sm"
          phx-click="open-editor"
          phx-value-kind="param_set"
        >
          <.icon name="hero-plus" class="size-4" /> Add parameter set
        </button>
      </:actions>
    </.section_header>

    <div class={[
      "mt-6 grid gap-5",
      @editor_kind == :param_set && "lg:grid-cols-[minmax(0,1fr)_24rem]"
    ]}>
      <div class={["min-w-0", @editor_kind == :param_set && "max-lg:hidden"]}>
        <.empty_state
          :if={@param_sets == []}
          id="param-sets-empty"
          title="No yt-dlp parameter sets"
          description="Create a set to control the format and extra arguments used for new downloads."
          icon="hero-command-line"
        >
          <:action>
            <button
              id="add-param-set-empty"
              type="button"
              class="btn btn-primary btn-sm"
              phx-click="open-editor"
              phx-value-kind="param_set"
            >
              Add parameter set
            </button>
          </:action>
        </.empty_state>

        <div
          :if={@param_sets != []}
          id="param-sets"
          class="divide-y divide-base-300 border-y border-base-300"
        >
          <div
            :for={param_set <- @param_sets}
            id={"param-set-#{param_set.id}"}
            class="grid gap-3 py-4 md:grid-cols-[minmax(10rem,1fr)_minmax(0,1.5fr)_auto] md:items-center"
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <h2 class="font-semibold text-base-content">{param_set.name}</h2>
                <span
                  :if={param_set.is_default}
                  class="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
                >
                  <.icon name="hero-check-badge" class="size-3.5" /> Default
                </span>
              </div>
              <div class="mt-2 flex flex-wrap gap-2">
                <.effect_badge status={:new_items} />
                <.effect_badge status={:stored_only} />
              </div>
            </div>
            <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-base-content/60">
              <div class="min-w-0">
                <dt class="text-base-content/40">Format</dt>
                <dd class="truncate">{param_set.format || "Built-in default"}</dd>
              </div>
              <div>
                <dt class="text-base-content/40">Rate limit</dt>
                <dd>
                  {if(param_set.rate_limit_kbps,
                    do: "#{param_set.rate_limit_kbps} kbps",
                    else: "Unlimited"
                  )}
                </dd>
              </div>
              <div>
                <dt class="text-base-content/40">Concurrency</dt>
                <dd>{param_set.concurrency || "Default"}</dd>
              </div>
              <div class="min-w-0">
                <dt class="text-base-content/40">Extra arguments</dt>
                <dd class="truncate">{param_set.extra_args || "None"}</dd>
              </div>
            </dl>
            <div class="flex flex-wrap items-center gap-1 md:justify-end">
              <button
                :if={!param_set.is_default}
                id={"default-param-set-#{param_set.id}"}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="set-default-param-set"
                phx-value-id={param_set.id}
              >
                Set default
              </button>
              <button
                id={"edit-param-set-#{param_set.id}"}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="open-editor"
                phx-value-kind="param_set"
                phx-value-id={param_set.id}
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </button>
              <button
                id={"delete-param-set-#{param_set.id}"}
                type="button"
                class="btn btn-ghost btn-sm text-error hover:bg-error/10"
                phx-click="delete-resource"
                phx-value-kind="param_set"
                phx-value-id={param_set.id}
                disabled={param_set.is_default}
                title={
                  param_set.is_default &&
                    "Set another parameter set as default before deleting this one."
                }
                data-confirm={"Delete parameter set #{param_set.name}? This cannot be undone."}
              >
                <.icon name="hero-trash" class="size-4" />
                <span class="sr-only">Delete {param_set.name}</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <.resource_editor
        :if={@editor_kind == :param_set}
        kind={@editor_kind}
        mode={@editor_mode}
        form={@editor_form}
        path_check={@path_check}
        editor_return_focus={@editor_return_focus}
        protected={false}
      />
    </div>
    """
  end

  def general_section(assigns) do
    ~H"""
    <.section_header
      title="General"
      description="Control application-wide scheduling behavior that can change safely while Ytdarr is running."
      icon="hero-cog-6-tooth"
    />

    <.form
      for={@general_form}
      id="general-form"
      phx-change="change-general"
      phx-submit="save-general"
      class="mt-2"
    >
      <.setting_row
        id="general-sync-interval"
        label="Automatic sync interval"
        description="Minutes between scheduled synchronization runs for monitored channels and playlists."
        effect={@setting_effects["sync_interval_minutes"]}
      >
        <:control>
          <.input
            field={@general_form[:sync_interval_minutes]}
            type="number"
            label="Interval in minutes"
            min="1"
            step="1"
          />
        </:control>
      </.setting_row>
    </.form>

    <.save_bar
      :if={@dirty_section == :general}
      section="General"
      form_id="general-form"
    />
    """
  end

  def system_section(assigns) do
    ~H"""
    <.section_header
      title="System"
      description="Inspect deployment configuration and capability checks. Restart-required values remain read-only in the browser."
      icon="hero-server-stack"
    />

    <div id="system-information" class="mt-5 border-y border-base-300">
      <.system_row
        :for={row <- @system_rows}
        id={row.id}
        label={row.label}
        value={row.value}
        description={row.description}
        sensitive={Map.get(row, :sensitive, false)}
        status={Map.get(row, :status)}
      />
    </div>

    <div class="mt-8 rounded-xl border border-warning/30 bg-warning/10 p-4 text-sm text-base-content/75">
      <div class="flex items-start gap-3">
        <.icon name="hero-shield-exclamation" class="mt-0.5 size-5 shrink-0 text-warning" />
        <div>
          <h2 class="font-semibold text-base-content">Local-network access</h2>
          <p class="mt-1 leading-6">
            Settings remain open under the current deployment model. The route stays isolated so a future administrator policy can protect it without redesigning this page.
            Do not expose Ytdarr directly to an untrusted network until authorization is enabled.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Editor panel
  # ---------------------------------------------------------------------------

  attr :kind, :atom, required: true
  attr :mode, :atom, required: true
  attr :form, :any, required: true
  attr :path_check, :any, default: nil
  attr :editor_return_focus, :string, required: true
  attr :protected, :boolean, default: false

  def resource_editor(assigns) do
    title =
      case {assigns.kind, assigns.mode} do
        {:root_folder, :create} -> "Add root folder"
        {:root_folder, :edit} -> "Edit root folder"
        {:profile, :create} -> "Add quality profile"
        {:profile, :edit} -> "Edit quality profile"
        {:param_set, :create} -> "Add parameter set"
        {:param_set, :edit} -> "Edit parameter set"
      end

    description =
      case assigns.kind do
        :root_folder ->
          "Use an absolute path that already exists and is writable by Ytdarr."

        :profile ->
          "Quality profiles are stored now and will be selectable when downloader support is added."

        :param_set ->
          "Format and extra arguments apply to downloads queued after this set becomes the default."
      end

    close =
      %Phoenix.LiveView.JS{}
      |> Phoenix.LiveView.JS.push("close-editor")
      |> Phoenix.LiveView.JS.focus(to: assigns.editor_return_focus)

    assigns = assign(assigns, title: title, description: description, close: close)

    ~H"""
    <.editor_panel
      id="settings-resource-editor"
      title={@title}
      description={@description}
      close={@close}
      return_focus={@editor_return_focus}
    >
      <.form
        for={@form}
        id="settings-editor-form"
        phx-change="validate-editor"
        phx-submit="save-editor"
        class="space-y-1"
      >
        <%= case @kind do %>
          <% :root_folder -> %>
            <.input field={@form[:path]} type="text" label="Absolute path" placeholder="/data/videos" />
            <.input
              field={@form[:purpose]}
              type="select"
              label="Purpose"
              options={[{"Videos", "videos"}, {"Music", "music"}, {"Podcasts", "podcasts"}]}
            />
            <.input
              field={@form[:active]}
              type="checkbox"
              label="Active"
              disabled={@protected}
            />
            <p :if={@protected} class="mb-3 flex items-center gap-2 text-sm text-warning">
              <.icon name="hero-shield-check" class="size-4" />
              Activate another root folder before deactivating this one.
            </p>
            <button
              id="validate-root-path"
              type="button"
              class="btn btn-ghost btn-sm mb-3"
              phx-click="validate-root-path"
              phx-disable-with="Checking..."
            >
              <.icon name="hero-folder-open" class="size-4" /> Check path
            </button>
            <.diagnostic_result :if={@path_check} id="root-path-result" result={@path_check} />
          <% :profile -> %>
            <.input field={@form[:name]} type="text" label="Name" placeholder="1080p" />
            <.input field={@form[:max_height]} type="number" label="Maximum height" min="1" />
            <.input
              :if={@mode == :create}
              field={@form[:is_default]}
              type="checkbox"
              label="Default profile"
            />
            <p
              :if={@mode == :edit && @form[:is_default].value}
              class="mb-3 flex items-center gap-2 text-sm text-primary"
            >
              <.icon name="hero-check-badge" class="size-4" />
              This is the default profile. Set another profile as default before deleting it.
            </p>
            <details class="group mt-4 border-t border-base-300 pt-4">
              <summary class="flex cursor-pointer list-none items-center justify-between text-sm font-semibold text-base-content">
                Advanced settings
                <.icon
                  name="hero-chevron-down"
                  class="size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <div class="mt-4">
                <.input
                  field={@form[:max_bitrate_kbps]}
                  type="number"
                  label="Maximum bitrate (kbps)"
                  min="1"
                />
                <.input
                  field={@form[:preferred_codecs]}
                  type="text"
                  label="Preferred codecs"
                  placeholder="av1, vp9, h264"
                />
                <.input field={@form[:allow_hdr]} type="checkbox" label="Allow HDR" />
                <.input
                  field={@form[:format_selector]}
                  type="text"
                  label="Raw yt-dlp format selector"
                  placeholder="bestvideo[height<=1080]+bestaudio/best"
                />
              </div>
            </details>
          <% :param_set -> %>
            <.input field={@form[:name]} type="text" label="Name" placeholder="Default" />
            <.input
              :if={@mode == :create}
              field={@form[:is_default]}
              type="checkbox"
              label="Default parameter set"
            />
            <p
              :if={@mode == :edit && @form[:is_default].value}
              class="mb-3 flex items-center gap-2 text-sm text-primary"
            >
              <.icon name="hero-check-badge" class="size-4" />
              This is the default set. Set another parameter set as default before deleting it.
            </p>
            <details class="group mt-4 border-t border-base-300 pt-4" open>
              <summary class="flex cursor-pointer list-none items-center justify-between text-sm font-semibold text-base-content">
                yt-dlp arguments
                <.icon
                  name="hero-chevron-down"
                  class="size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <div class="mt-4">
                <.input field={@form[:format]} type="text" label="Format" placeholder="bv*+ba/b" />
                <.input
                  field={@form[:extra_args]}
                  type="textarea"
                  label="Extra arguments"
                  placeholder="--embed-metadata"
                  rows="3"
                />
              </div>
            </details>
            <details class="group mt-4 border-t border-base-300 pt-4">
              <summary class="flex cursor-pointer list-none items-center justify-between text-sm font-semibold text-base-content">
                Stored for future support
                <.icon
                  name="hero-chevron-down"
                  class="size-4 transition-transform group-open:rotate-180"
                />
              </summary>
              <div class="mt-4">
                <.input
                  field={@form[:rate_limit_kbps]}
                  type="number"
                  label="Rate limit (kbps)"
                  min="1"
                />
                <.input field={@form[:concurrency]} type="number" label="Concurrency" min="1" />
              </div>
            </details>
        <% end %>

        <div class="mt-5 flex items-center justify-end gap-2 border-t border-base-300 pt-4">
          <button
            id="settings-editor-cancel"
            type="button"
            class="btn btn-ghost btn-sm"
            phx-click={@close}
          >
            Cancel
          </button>
          <button
            id="settings-editor-submit"
            type="submit"
            class="btn btn-primary btn-sm"
            phx-disable-with="Saving..."
          >
            {if(@mode == :create, do: "Create", else: "Save changes")}
          </button>
        </div>
      </.form>
    </.editor_panel>
    """
  end

  # ---------------------------------------------------------------------------
  # Diagnostic result
  # ---------------------------------------------------------------------------

  attr :id, :string, required: true
  attr :result, :any, required: true

  def diagnostic_result(assigns) do
    ~H"""
    <div
      id={@id}
      role="status"
      class={[
        "mt-3 flex items-start gap-2 rounded-lg px-3 py-2 text-sm",
        elem(@result, 0) == :ok && "bg-success/15 text-success",
        elem(@result, 0) == :error && "bg-error/15 text-error"
      ]}
    >
      <.icon
        name={if(elem(@result, 0) == :ok, do: "hero-check-circle", else: "hero-exclamation-circle")}
        class="mt-0.5 size-4 shrink-0"
      />
      <span>{elem(@result, 1)}</span>
    </div>
    """
  end

  attr :result, :any, required: true

  defp root_folder_health_badge(assigns) do
    {label, icon, classes} =
      case assigns.result do
        :ok ->
          {"Writable", "hero-check-circle", "bg-success/15 text-success"}

        {:error, :not_found} ->
          {"Missing", "hero-exclamation-circle", "bg-error/15 text-error"}

        {:error, :not_directory} ->
          {"Not a directory", "hero-exclamation-circle", "bg-error/15 text-error"}

        {:error, :not_writable} ->
          {"Not writable", "hero-exclamation-circle", "bg-error/15 text-error"}

        _ ->
          {"Invalid path", "hero-exclamation-circle", "bg-error/15 text-error"}
      end

    assigns = assign(assigns, label: label, icon: icon, classes: classes)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium",
      @classes
    ]}>
      <.icon name={@icon} class="size-3.5" />
      {@label}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Presentational helpers
  # ---------------------------------------------------------------------------

  defp codec_summary([]), do: "Any"
  defp codec_summary(nil), do: "Any"
  defp codec_summary(codecs), do: Enum.join(codecs, ", ")

  defp youtube_key_description(:environment) do
    "Managed by YTDARR_YOUTUBE_API_KEY. Change the deployment environment and restart Ytdarr to replace it."
  end

  defp youtube_key_description(:database) do
    "A browser-managed key is configured. Enter a new value only when replacing it."
  end

  defp youtube_key_description(:unset) do
    "Required for YouTube metadata and channel discovery. The value is stored securely and never shown again."
  end
end
