defmodule Ytdarr.Content.Channel do
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Content,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "channels"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :external_id, :platform, :is_monitored, :inserted_at]
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :external_id, :string do
      allow_nil? false
      public? true
      description "YouTube channel id, etc."
    end

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :platform, :string do
      allow_nil? false
      public? true
      default "YouTube"
      description "e.g., YouTube, Twitch"
    end

    attribute :avatar_url, :string do
      public? true
      description "Platform thumbnail/avatar url"
    end

    attribute :banner_url, :string do
      public? true
      description "Platform banner url"
    end

    attribute :platform_username, :string do
      public? true
    end

    # Monitoring status
    attribute :is_monitored, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :is_monitored_since, :utc_datetime do
      public? true
    end

    attribute :last_checked_at, :utc_datetime do
      public? true
    end

    # Filesystem paths
    attribute :base_path, :string do
      public? true
      description "e.g., /downloads/channels/channel_name"
    end

    attribute :generic_video_path, :string do
      public? true
      description "e.g., /downloads/channels/channel_name/videos"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :videos, Ytdarr.Content.Video
    has_many :playlists, Ytdarr.Content.Playlist
  end

  identities do
    identity :unique_external_id, [:external_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :external_id,
        :url,
        :description,
        :platform,
        :avatar_url,
        :banner_url,
        :platform_username,
        :is_monitored
      ]

      change Ytdarr.Content.Channel.Changes.SetFilesystemPaths
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
    end

    update :update do
      require_atomic? false

      accept [
        :name,
        :external_id,
        :url,
        :description,
        :platform,
        :avatar_url,
        :banner_url,
        :platform_username,
        :is_monitored,
        :last_checked_at
      ]

      change Ytdarr.Content.Channel.Changes.SetFilesystemPaths
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
    end

    update :monitor do
      require_atomic? false
      accept []
      change set_attribute(:is_monitored, true)
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
      change Ytdarr.Content.Channel.Changes.QueueSync
    end

    update :unmonitor do
      require_atomic? false
      accept []
      change set_attribute(:is_monitored, false)
      change set_attribute(:is_monitored_since, nil)
    end

    update :toggle_monitor do
      require_atomic? false
      accept []
      change Ytdarr.Content.Channel.Changes.ToggleMonitor
      change Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp
    end

    update :mark_checked do
      require_atomic? false
      accept []
      change set_attribute(:last_checked_at, &DateTime.utc_now/0)
    end
  end

  validations do
    validate {Ytdarr.Content.Channel.Validations.ValidUrl, attribute: :url}
  end
end

defmodule Ytdarr.Content.Channel.Validations.ValidUrl do
  @moduledoc "Validates that the URL is a valid http or https URL"
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    url = Ash.Changeset.get_attribute(changeset, opts[:attribute])

    if is_nil(url) do
      :ok
    else
      case URI.parse(url) do
        %URI{scheme: nil} ->
          {:error, field: opts[:attribute], message: "must have a scheme (http or https)"}

        %URI{host: nil} ->
          {:error, field: opts[:attribute], message: "must have a host"}

        %URI{scheme: scheme} when scheme in ["http", "https"] ->
          :ok

        _ ->
          {:error, field: opts[:attribute], message: "must be a valid http or https URL"}
      end
    end
  end
end

defmodule Ytdarr.Content.Channel.Changes.SetFilesystemPaths do
  @moduledoc "Sets base_path and generic_video_path when name changes"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      nil ->
        changeset

      name ->
        configured_base_path = Ytdarr.Settings.get_app_media_root_folder!()
        sanitized_name = sanitize_filename(name)
        base_path = Path.join([configured_base_path, sanitized_name])

        changeset
        |> Ash.Changeset.force_change_attribute(:base_path, base_path)
        |> Ash.Changeset.force_change_attribute(:generic_video_path, generic_video_path)
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.downcase()
  end
end

defmodule Ytdarr.Content.Channel.Changes.SetMonitoredTimestamp do
  @moduledoc "Sets is_monitored_since when transitioning to monitored"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    is_monitored = Ash.Changeset.get_attribute(changeset, :is_monitored)
    existing_since = Ash.Changeset.get_attribute(changeset, :is_monitored_since)

    cond do
      is_monitored == true and is_nil(existing_since) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :is_monitored_since,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )

      is_monitored == false ->
        Ash.Changeset.force_change_attribute(changeset, :is_monitored_since, nil)

      true ->
        changeset
    end
  end
end

defmodule Ytdarr.Content.Channel.Changes.ToggleMonitor do
  @moduledoc "Toggles the is_monitored status"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    current = Ash.Changeset.get_attribute(changeset, :is_monitored)
    new_value = not current

    changeset =
      Ash.Changeset.force_change_attribute(changeset, :is_monitored, new_value)

    if new_value do
      Ash.Changeset.after_action(changeset, fn _changeset, result ->
        Oban.insert(%Oban.Job{
          worker: Ytdarr.ObanWorkers.SyncWorker,
          args: %{"source_type" => "channel", "source_id" => result.id}
        })

        {:ok, result}
      end)
    else
      changeset
    end
  end
end

defmodule Ytdarr.Content.Channel.Changes.QueueSync do
  @moduledoc "Queues a sync job after the channel is monitored"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      Oban.insert(%Oban.Job{
        worker: Ytdarr.ObanWorkers.SyncWorker,
        args: %{"source_type" => "channel", "source_id" => result.id}
      })

      {:ok, result}
    end)
  end
end
