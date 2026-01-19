defmodule Ytdarr.Content.Playlist do
  use Ash.Resource,
    otp_app: :ytdarr,
    domain: Ytdarr.Content,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshAdmin.Resource]

  sqlite do
    table "playlists"
    repo Ytdarr.Repo
  end

  admin do
    table_columns [:id, :name, :external_id, :video_count, :is_monitored, :inserted_at]
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
      description "YouTube playlist id, etc."
    end

    attribute :url, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :video_count, :integer do
      public? true
      description "Number of videos in the playlist"
    end

    # Monitoring
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

    # Filesystem
    attribute :download_path, :string do
      public? true
      description "channel base path + /playlist_name"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :channel, Ytdarr.Content.Channel do
      attribute_type :integer
      allow_nil? false
    end

    many_to_many :videos, Ytdarr.Content.Video do
      through Ytdarr.Content.PlaylistVideo
      source_attribute_on_join_resource :playlist_id
      destination_attribute_on_join_resource :video_id
    end
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
        :video_count,
        :is_monitored
      ]

      argument :channel_id, :integer do
        allow_nil? false
      end

      change manage_relationship(:channel_id, :channel, type: :append)
      change Ytdarr.Content.Playlist.Changes.SetDownloadPath
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
    end

    update :update do
      require_atomic? false
      accept [
        :name,
        :description,
        :video_count,
        :is_monitored,
        :last_checked_at
      ]

      change Ytdarr.Content.Playlist.Changes.SetDownloadPath
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
    end

    update :monitor do
      require_atomic? false
      accept []
      change set_attribute(:is_monitored, true)
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
      change Ytdarr.Content.Playlist.Changes.QueueSync
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
      change Ytdarr.Content.Playlist.Changes.ToggleMonitor
      change Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp
    end

    update :mark_checked do
      require_atomic? false
      accept []
      change set_attribute(:last_checked_at, &DateTime.utc_now/0)
    end
  end
end

defmodule Ytdarr.Content.Playlist.Changes.SetDownloadPath do
  @moduledoc "Sets download_path based on channel base_path and playlist name"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    name = Ash.Changeset.get_attribute(changeset, :name)

    # Try to get channel from the data or load it
    channel =
      case Ash.Changeset.get_data(changeset, :channel) do
        %Ytdarr.Content.Channel{} = ch -> ch
        _ -> nil
      end

    case {channel, name} do
      {%{base_path: base_path}, name} when not is_nil(name) and not is_nil(base_path) ->
        sanitized_name = sanitize_filename(name)
        download_path = Path.join([base_path, sanitized_name])
        Ash.Changeset.force_change_attribute(changeset, :download_path, download_path)

      _ ->
        changeset
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "_")
    |> String.downcase()
  end
end

defmodule Ytdarr.Content.Playlist.Changes.SetMonitoredTimestamp do
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

defmodule Ytdarr.Content.Playlist.Changes.ToggleMonitor do
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
          args: %{"source_type" => "playlist", "source_id" => result.id}
        })

        {:ok, result}
      end)
    else
      changeset
    end
  end
end

defmodule Ytdarr.Content.Playlist.Changes.QueueSync do
  @moduledoc "Queues a sync job after the playlist is monitored"
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      Oban.insert(%Oban.Job{
        worker: Ytdarr.ObanWorkers.SyncWorker,
        args: %{"source_type" => "playlist", "source_id" => result.id}
      })

      {:ok, result}
    end)
  end
end
