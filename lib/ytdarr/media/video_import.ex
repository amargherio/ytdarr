defmodule Ytdarr.Media.VideoImport do
  @moduledoc """
  A no-overwrite, recoverable filesystem transaction for importing one existing
  video into Ytdarr's canonical media layout.

  The module keeps every durable mutation in an ownership journal. Staged files
  remain hard-linked to their final paths until the database transition has
  completed, and source files remain in an exclusively-owned quarantine until
  cleanup is safe. This lets failed workers restore sources without guessing
  which files belong to them.
  """

  alias Ytdarr.{MediaPermissions}
  alias Ytdarr.Media.{Ffprobe, VideoArtifacts}
  alias Ytdarr.Media.VideoArtifacts.Destination

  @video_extensions MapSet.new(
                      ~w(.mp4 .mkv .webm .mov .m4v .avi .mpg .mpeg .ts .m2ts .wmv .flv .ogv)
                    )
  @subtitle_extensions MapSet.new(~w(.srt .vtt .ass .ssa))
  @artwork_extensions MapSet.new(~w(.jpg .jpeg .png .webp))
  @probe_timeout 15_000

  defmodule Fingerprint do
    @moduledoc false

    @enforce_keys [:major_device, :minor_device, :inode, :size, :mtime]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            major_device: non_neg_integer(),
            minor_device: non_neg_integer(),
            inode: non_neg_integer(),
            size: non_neg_integer(),
            mtime: integer()
          }

    @spec from_stat(File.Stat.t() | map()) :: t()
    def from_stat(stat) when is_map(stat) do
      %__MODULE__{
        major_device: Map.get(stat, :major_device),
        minor_device: Map.get(stat, :minor_device),
        inode: Map.get(stat, :inode),
        size: Map.get(stat, :size),
        mtime: posix_mtime(Map.get(stat, :mtime))
      }
    end

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = fingerprint) do
      %{
        "major_device" => fingerprint.major_device,
        "minor_device" => fingerprint.minor_device,
        "inode" => fingerprint.inode,
        "size" => fingerprint.size,
        "mtime" => fingerprint.mtime
      }
    end

    @spec from_map(map()) :: {:ok, t()} | {:error, term()}
    def from_map(map) when is_map(map) do
      with {:ok, major_device} <- integer_field(map, "major_device"),
           {:ok, minor_device} <- integer_field(map, "minor_device"),
           {:ok, inode} <- integer_field(map, "inode"),
           {:ok, size} <- integer_field(map, "size"),
           {:ok, mtime} <- integer_field(map, "mtime") do
        {:ok,
         %__MODULE__{
           major_device: major_device,
           minor_device: minor_device,
           inode: inode,
           size: size,
           mtime: mtime
         }}
      end
    end

    def from_map(_map), do: {:error, :invalid_fingerprint}

    defp integer_field(map, key) do
      case Map.fetch(map, key) do
        {:ok, value} when is_integer(value) and value >= 0 -> {:ok, value}
        _ -> {:error, :invalid_fingerprint}
      end
    end

    defp posix_mtime(value) when is_integer(value), do: value

    defp posix_mtime({{year, month, day}, {hour, minute, second}}) do
      epoch = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

      :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}}) -
        epoch
    end

    defp posix_mtime(_value), do: 0
  end

  defmodule Artifact do
    @moduledoc false

    @enforce_keys [:id, :kind, :source_path, :destination_path, :fingerprint]
    defstruct @enforce_keys

    @type kind :: :media | :subtitle | :artwork | :source_nfo
    @type t :: %__MODULE__{
            id: String.t(),
            kind: kind(),
            source_path: Path.t(),
            destination_path: Path.t() | nil,
            fingerprint: Fingerprint.t()
          }

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = artifact) do
      %{
        "id" => artifact.id,
        "kind" => Atom.to_string(artifact.kind),
        "source_path" => artifact.source_path,
        "destination_path" => artifact.destination_path,
        "fingerprint" => Fingerprint.to_map(artifact.fingerprint)
      }
    end

    @spec from_map(map()) :: {:ok, t()} | {:error, term()}
    def from_map(map) when is_map(map) do
      with {:ok, id} <- string_field(map, "id"),
           {:ok, kind} <- kind_field(Map.get(map, "kind")),
           {:ok, source_path} <- absolute_path_field(map, "source_path"),
           {:ok, destination_path} <- optional_absolute_path_field(map, "destination_path"),
           {:ok, fingerprint} <- Fingerprint.from_map(Map.get(map, "fingerprint")) do
        {:ok,
         %__MODULE__{
           id: id,
           kind: kind,
           source_path: source_path,
           destination_path: destination_path,
           fingerprint: fingerprint
         }}
      end
    end

    def from_map(_map), do: {:error, :invalid_artifact}

    defp kind_field("media"), do: {:ok, :media}
    defp kind_field("subtitle"), do: {:ok, :subtitle}
    defp kind_field("artwork"), do: {:ok, :artwork}
    defp kind_field("source_nfo"), do: {:ok, :source_nfo}
    defp kind_field(_value), do: {:error, :invalid_artifact}

    defp string_field(map, key) do
      case Map.fetch(map, key) do
        {:ok, value} when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
        _ -> {:error, :invalid_artifact}
      end
    end

    defp absolute_path_field(map, key) do
      with {:ok, path} <- string_field(map, key),
           true <- Path.type(path) == :absolute do
        {:ok, path}
      else
        _ -> {:error, :invalid_artifact}
      end
    end

    defp optional_absolute_path_field(map, key) do
      case Map.get(map, key) do
        nil ->
          {:ok, nil}

        value when is_binary(value) ->
          if Path.type(value) == :absolute, do: {:ok, value}, else: {:error, :invalid_artifact}

        _ ->
          {:error, :invalid_artifact}
      end
    end
  end

  defmodule Preview do
    @moduledoc false

    @enforce_keys [
      :video_id,
      :channel_id,
      :source,
      :sidecars,
      :source_nfo,
      :destination,
      :quality,
      :inspected_at
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            video_id: integer(),
            channel_id: integer(),
            source: Artifact.t(),
            sidecars: [Artifact.t()],
            source_nfo: Artifact.t() | nil,
            destination: Destination.t(),
            quality: String.t() | nil,
            inspected_at: DateTime.t()
          }
  end

  defmodule Manifest do
    @moduledoc false

    alias Ytdarr.Media.VideoImport.Artifact
    alias Ytdarr.Media.VideoArtifacts.Destination

    @enforce_keys [
      :video_id,
      :channel_id,
      :source,
      :sidecars,
      :source_nfo,
      :destination,
      :quality,
      :inspected_at,
      :selected_sidecar_ids
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            video_id: integer(),
            channel_id: integer(),
            source: Artifact.t(),
            sidecars: [Artifact.t()],
            source_nfo: Artifact.t() | nil,
            destination: Destination.t(),
            quality: String.t() | nil,
            inspected_at: DateTime.t(),
            selected_sidecar_ids: [String.t()]
          }

    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = manifest) do
      %{
        "video_id" => manifest.video_id,
        "channel_id" => manifest.channel_id,
        "source" => Artifact.to_map(manifest.source),
        "sidecars" => Enum.map(manifest.sidecars, &Artifact.to_map/1),
        "source_nfo" => nullable_artifact_map(manifest.source_nfo),
        "destination" => destination_to_map(manifest.destination),
        "quality" => manifest.quality,
        "inspected_at" => DateTime.to_iso8601(manifest.inspected_at),
        "selected_sidecar_ids" => manifest.selected_sidecar_ids
      }
    end

    @spec from_map(map()) :: {:ok, t()} | {:error, term()}
    def from_map(map) when is_map(map) do
      with {:ok, video_id} <- positive_integer_field(map, "video_id"),
           {:ok, channel_id} <- positive_integer_field(map, "channel_id"),
           {:ok, source} <- Artifact.from_map(Map.get(map, "source")),
           :ok <- ensure_source_media(source),
           {:ok, sidecars} <- artifact_list(Map.get(map, "sidecars")),
           :ok <- ensure_sidecars(sidecars),
           {:ok, source_nfo} <- nullable_source_nfo(Map.get(map, "source_nfo")),
           {:ok, destination} <- destination_from_map(Map.get(map, "destination")),
           {:ok, quality} <- nullable_string_field(map, "quality"),
           {:ok, inspected_at} <- datetime_field(map, "inspected_at"),
           {:ok, selected_sidecar_ids} <- selected_ids_field(map),
           :ok <- ensure_selected_ids(sidecars, selected_sidecar_ids) do
        {:ok,
         %__MODULE__{
           video_id: video_id,
           channel_id: channel_id,
           source: source,
           sidecars: sidecars,
           source_nfo: source_nfo,
           destination: destination,
           quality: quality,
           inspected_at: inspected_at,
           selected_sidecar_ids: selected_sidecar_ids
         }}
      end
    end

    def from_map(_map), do: {:error, :invalid_manifest}

    defp nullable_artifact_map(nil), do: nil
    defp nullable_artifact_map(artifact), do: Artifact.to_map(artifact)

    defp destination_to_map(%Destination{} = destination) do
      %{
        "season_directory" => destination.season_directory,
        "basename" => destination.basename,
        "media_path" => destination.media_path,
        "nfo_path" => destination.nfo_path,
        "episode_number" => destination.episode_number,
        "extension" => destination.extension
      }
    end

    defp destination_from_map(map) when is_map(map) do
      with {:ok, season_directory} <- absolute_string(map, "season_directory"),
           {:ok, basename} <- nonempty_string(map, "basename"),
           {:ok, media_path} <- absolute_string(map, "media_path"),
           {:ok, nfo_path} <- absolute_string(map, "nfo_path"),
           {:ok, episode_number} <- positive_integer_field(map, "episode_number"),
           {:ok, extension} <- nonempty_string(map, "extension"),
           true <- String.starts_with?(extension, ".") do
        {:ok,
         %Destination{
           season_directory: season_directory,
           basename: basename,
           media_path: media_path,
           nfo_path: nfo_path,
           episode_number: episode_number,
           extension: extension
         }}
      else
        _ -> {:error, :invalid_manifest}
      end
    end

    defp destination_from_map(_map), do: {:error, :invalid_manifest}

    defp artifact_list(list) when is_list(list) do
      Enum.reduce_while(list, {:ok, []}, fn item, {:ok, artifacts} ->
        case Artifact.from_map(item) do
          {:ok, artifact} -> {:cont, {:ok, [artifact | artifacts]}}
          {:error, _reason} -> {:halt, {:error, :invalid_manifest}}
        end
      end)
      |> case do
        {:ok, artifacts} -> {:ok, Enum.reverse(artifacts)}
        error -> error
      end
    end

    defp artifact_list(_list), do: {:error, :invalid_manifest}

    defp nullable_source_nfo(nil), do: {:ok, nil}

    defp nullable_source_nfo(map) do
      with {:ok, artifact} <- Artifact.from_map(map),
           :source_nfo <- artifact.kind do
        {:ok, artifact}
      else
        _ -> {:error, :invalid_manifest}
      end
    end

    defp ensure_source_media(%Artifact{kind: :media}), do: :ok
    defp ensure_source_media(_source), do: {:error, :invalid_manifest}

    defp ensure_sidecars(sidecars) do
      ids = Enum.map(sidecars, & &1.id)

      if Enum.all?(sidecars, &(&1.kind in [:subtitle, :artwork])) and
           length(ids) == MapSet.size(MapSet.new(ids)) do
        :ok
      else
        {:error, :invalid_manifest}
      end
    end

    defp selected_ids_field(map) do
      case Map.get(map, "selected_sidecar_ids") do
        ids when is_list(ids) ->
          if Enum.all?(ids, &(is_binary(&1) and byte_size(&1) > 0)) do
            {:ok, ids}
          else
            {:error, :invalid_manifest}
          end

        _ ->
          {:error, :invalid_manifest}
      end
    end

    defp ensure_selected_ids(sidecars, selected_ids) do
      known_ids = MapSet.new(Enum.map(sidecars, & &1.id))

      if length(selected_ids) == MapSet.size(MapSet.new(selected_ids)) and
           Enum.all?(selected_ids, &MapSet.member?(known_ids, &1)) do
        :ok
      else
        {:error, :invalid_manifest}
      end
    end

    defp positive_integer_field(map, key) do
      case Map.get(map, key) do
        value when is_integer(value) and value > 0 -> {:ok, value}
        _ -> {:error, :invalid_manifest}
      end
    end

    defp nonempty_string(map, key) do
      case Map.get(map, key) do
        value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
        _ -> {:error, :invalid_manifest}
      end
    end

    defp absolute_string(map, key) do
      with {:ok, path} <- nonempty_string(map, key),
           true <- Path.type(path) == :absolute do
        {:ok, path}
      else
        _ -> {:error, :invalid_manifest}
      end
    end

    defp nullable_string_field(map, key) do
      case Map.get(map, key) do
        nil -> {:ok, nil}
        value when is_binary(value) -> {:ok, value}
        _ -> {:error, :invalid_manifest}
      end
    end

    defp datetime_field(map, key) do
      case Map.get(map, key) do
        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _offset} -> {:ok, datetime}
            _ -> {:error, :invalid_manifest}
          end

        _ ->
          {:error, :invalid_manifest}
      end
    end
  end

  defmodule DestinationPair do
    @moduledoc false

    @enforce_keys [:id, :kind, :marker_path, :final_path, :marker_fingerprint, :final_fingerprint]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            id: String.t() | atom(),
            kind: :media | :subtitle | :artwork | :nfo | :unknown,
            marker_path: Path.t(),
            final_path: Path.t(),
            marker_fingerprint: Fingerprint.t() | nil,
            final_fingerprint: Fingerprint.t() | nil
          }
  end

  defmodule SourceMapping do
    @moduledoc false

    @enforce_keys [:kind, :original_path, :quarantine_path, :fingerprint]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            kind: Artifact.kind() | :unknown,
            original_path: Path.t(),
            quarantine_path: Path.t(),
            fingerprint: Fingerprint.t() | nil
          }
  end

  defmodule Placement do
    @moduledoc false

    @enforce_keys [
      :job_id,
      :manifest,
      :lock_path,
      :lock_fingerprint,
      :destination_pairs,
      :source_quarantine_directory,
      :quarantine_owner_path,
      :quarantine_owner_fingerprint,
      :source_mappings,
      :file_size,
      :quality
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            job_id: pos_integer(),
            manifest: Manifest.t() | nil,
            lock_path: Path.t(),
            lock_fingerprint: Fingerprint.t() | nil,
            destination_pairs: [DestinationPair.t()],
            source_quarantine_directory: Path.t() | nil,
            quarantine_owner_path: Path.t() | nil,
            quarantine_owner_fingerprint: Fingerprint.t() | nil,
            source_mappings: [SourceMapping.t()],
            file_size: non_neg_integer() | nil,
            quality: String.t() | nil
          }
  end

  defmodule FileOps do
    @moduledoc "Filesystem seam used by import tests and the production transaction."

    @callback lstat(context :: term(), path :: Path.t()) ::
                {:ok, File.Stat.t() | map()} | {:error, term()}
    @callback stat(context :: term(), path :: Path.t(), options :: keyword()) ::
                {:ok, File.Stat.t() | map()} | {:error, term()}
    @callback list(context :: term(), path :: Path.t()) :: {:ok, [String.t()]} | {:error, term()}
    @callback mkdir(context :: term(), path :: Path.t()) :: :ok | {:error, term()}
    @callback create_exclusive(context :: term(), path :: Path.t(), contents :: iodata()) ::
                :ok | {:error, term()}
    @callback copy(context :: term(), source :: Path.t(), destination :: Path.t()) ::
                :ok | {:error, term()}
    @callback hard_link(context :: term(), source :: Path.t(), destination :: Path.t()) ::
                :ok | {:error, term()}
    @callback rename(context :: term(), source :: Path.t(), destination :: Path.t()) ::
                :ok | {:error, term()}
    @callback remove(context :: term(), path :: Path.t()) :: :ok | {:error, term()}
    @callback remove_dir(context :: term(), path :: Path.t()) :: :ok | {:error, term()}
    @callback touch(context :: term(), path :: Path.t(), time :: integer()) ::
                :ok | {:error, term()}

    defmodule Real do
      @moduledoc false
      @behaviour Ytdarr.Media.VideoImport.FileOps

      @impl true
      def lstat(_context, path), do: File.lstat(path, time: :posix)

      @impl true
      def stat(_context, path, options), do: File.stat(path, options)

      @impl true
      def list(_context, path), do: File.ls(path)

      @impl true
      def mkdir(_context, path), do: File.mkdir(path)

      @impl true
      def create_exclusive(_context, path, contents),
        do: File.write(path, contents, [:exclusive, :binary])

      @impl true
      def copy(_context, source, destination), do: File.cp(source, destination)

      @impl true
      def hard_link(_context, source, destination), do: File.ln(source, destination)

      @impl true
      def rename(_context, source, destination), do: File.rename(source, destination)

      @impl true
      def remove(_context, path), do: File.rm(path)

      @impl true
      def remove_dir(_context, path), do: File.rmdir(path)

      @impl true
      def touch(_context, path, time), do: File.touch(path, time)
    end
  end

  @doc """
  Inspects a source video and every supported same-directory companion without
  following a symlink. The returned preview is immutable input to manifest
  construction and queueing.
  """
  @spec inspect_source(struct(), struct(), Path.t(), keyword()) ::
          {:ok, Preview.t()} | {:error, term()}
  def inspect_source(channel, video, source_path, opts \\ [])

  def inspect_source(channel, video, source_path, opts)
      when is_binary(source_path) and is_list(opts) do
    ops = file_ops(opts)
    source_path = Path.expand(source_path)

    with {:ok, source} <- source_artifact(source_path, ops),
         :ok <- ensure_video_extension(source_path),
         :ok <- ensure_readable(source_path),
         :ok <- ensure_source_directory_writable(Path.dirname(source_path), ops),
         {:ok, destination} <-
           VideoArtifacts.build_destination(channel, video, Path.extname(source_path)),
         source = %{source | destination_path: destination.media_path},
         {:ok, sidecars, source_nfo} <- discover_companions(source, destination, ops),
         :ok <- ensure_initial_destination_available(destination, ops),
         {:ok, probe_result} <- probe(opts).probe(source_path, probe_timeout(opts)) do
      {:ok,
       %Preview{
         video_id: Map.fetch!(video, :id),
         channel_id: Map.fetch!(channel, :id),
         source: source,
         sidecars: sidecars,
         source_nfo: source_nfo,
         destination: destination,
         quality: Map.get(probe_result, :quality),
         inspected_at: DateTime.utc_now() |> DateTime.truncate(:second)
       }}
    else
      {:error, reason} -> {:error, normalize_inspection_error(reason)}
    end
  end

  def inspect_source(_channel, _video, _source_path, _opts), do: {:error, :video_not_importable}

  @doc "Builds a JSON-persistable import manifest from a retained preview."
  @spec build_manifest(Preview.t(), [String.t()]) ::
          {:ok, Manifest.t()} | {:error, :invalid_sidecar_selection}
  def build_manifest(%Preview{} = preview, selected_sidecar_ids)
      when is_list(selected_sidecar_ids) do
    selected_ids = Enum.uniq(selected_sidecar_ids)
    known_ids = MapSet.new(Enum.map(preview.sidecars, & &1.id))

    if length(selected_ids) == length(selected_sidecar_ids) and
         Enum.all?(selected_ids, &(is_binary(&1) and MapSet.member?(known_ids, &1))) do
      {:ok,
       %Manifest{
         video_id: preview.video_id,
         channel_id: preview.channel_id,
         source: preview.source,
         sidecars: preview.sidecars,
         source_nfo: preview.source_nfo,
         destination: preview.destination,
         quality: preview.quality,
         inspected_at: preview.inspected_at,
         selected_sidecar_ids: selected_ids
       }}
    else
      {:error, :invalid_sidecar_selection}
    end
  end

  def build_manifest(_preview, _selected_sidecar_ids), do: {:error, :invalid_sidecar_selection}

  @doc false
  @spec preview_matches?(Preview.t(), Preview.t()) :: boolean()
  def preview_matches?(%Preview{} = left, %Preview{} = right) do
    left.video_id == right.video_id and
      left.channel_id == right.channel_id and
      immutable_artifact?(left.source, right.source) and
      immutable_artifacts?(left.sidecars, right.sidecars) and
      nullable_artifact_equal?(left.source_nfo, right.source_nfo) and
      left.destination == right.destination
  end

  def preview_matches?(_left, _right), do: false

  @doc """
  Stages, no-overwrite-promotes, and quarantines an import. The returned
  placement remains intentionally incomplete until its caller records the
  downloaded state and invokes `commit_cleanup/2`.
  """
  @spec stage(pos_integer(), Manifest.t(), struct(), struct(), keyword()) ::
          {:ok, Placement.t()} | {:error, term(), [map()]}
  def stage(job_id, manifest, channel, video, opts \\ [])

  def stage(job_id, %Manifest{} = manifest, channel, video, opts)
      when is_integer(job_id) and job_id > 0 and is_list(opts) do
    ops = file_ops(opts)

    with :ok <- validate_manifest(manifest),
         :ok <- validate_stage_identity(manifest, channel, video),
         :ok <- validate_stale_preview(manifest, channel, video, ops),
         :ok <- ensure_selected_destination_available(manifest, ops),
         {:ok, policy} <- load_policy(opts),
         :ok <- permissions(opts).mkdir_p(manifest.destination.season_directory, policy) do
      placement = initial_placement(job_id, manifest)
      do_stage(placement, channel, video, policy, opts)
    else
      {:error, reason} -> {:error, normalize_stage_error(reason), []}
    end
  end

  def stage(_job_id, _manifest, _channel, _video, _opts), do: {:error, :source_changed, []}

  @doc "Restores quarantined sources and removes only marker-proven finals."
  @spec rollback(Placement.t(), keyword()) :: {:ok, []} | {:error, [map()]}
  def rollback(%Placement{} = placement, opts \\ []) when is_list(opts) do
    ops = file_ops(opts)
    owner_status = quarantine_owner_status(placement, ops)
    remaining_mappings = rollback_source_mappings(placement.source_mappings, owner_status, ops)
    remaining_pairs = rollback_destination_pairs(placement.destination_pairs, ops)
    remaining_lock = cleanup_lock(placement, ops)
    remaining_owner = cleanup_quarantine_owner(placement, remaining_mappings, owner_status, ops)

    entries =
      source_mapping_entries(remaining_mappings, placement.job_id) ++
        destination_pair_entries(remaining_pairs, placement.job_id) ++
        lock_entry(remaining_lock, placement.job_id) ++
        owner_entry(remaining_owner, placement.job_id)

    result_from_entries(entries)
  end

  @doc "Deletes only owned staging/quarantine artifacts after downloaded commits."
  @spec commit_cleanup(Placement.t(), keyword()) :: {:ok, []} | {:error, [map()]}
  def commit_cleanup(%Placement{} = placement, opts \\ []) when is_list(opts) do
    ops = file_ops(opts)
    owner_status = quarantine_owner_status(placement, ops)
    remaining_pairs = cleanup_destination_markers(placement.destination_pairs, ops)
    remaining_mappings = cleanup_quarantined_sources(placement.source_mappings, owner_status, ops)
    remaining_lock = cleanup_lock(placement, ops)
    remaining_owner = cleanup_quarantine_owner(placement, remaining_mappings, owner_status, ops)

    entries =
      source_mapping_entries(remaining_mappings, placement.job_id) ++
        destination_pair_entries(remaining_pairs, placement.job_id) ++
        lock_entry(remaining_lock, placement.job_id) ++
        owner_entry(remaining_owner, placement.job_id)

    result_from_entries(entries)
  end

  @doc """
  Reconstructs a transaction from a live job manifest, or from the persisted
  ownership journal supplied in `opts[:recovery]`. Persisted journals are
  authoritative after lifecycle actions clear the job and manifest fields.
  """
  @spec recover(integer() | nil, Manifest.t() | map() | nil, atom() | String.t(), keyword()) ::
          {:ok, []} | {:error, [map()]}
  def recover(job_id, manifest, state, opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :recovery) do
      %{"entries" => [_ | _]} = recovery ->
        recover_persisted(recovery, state, opts)

      %{"entries" => []} ->
        {:ok, []}

      nil ->
        recover_from_manifest(job_id, manifest, state, opts)

      _invalid_recovery ->
        {:error, []}
    end
  end

  @doc "Returns the fixed JSON-safe recovery envelope for a placement or entries."
  @spec recovery_map(Placement.t() | [map()], :restore | :delete) :: map()
  def recovery_map(%Placement{} = placement, mode) when mode in [:restore, :delete] do
    %{"mode" => Atom.to_string(mode), "entries" => recovery_entries(placement)}
  end

  def recovery_map(entries, mode) when is_list(entries) and mode in [:restore, :delete] do
    %{"mode" => Atom.to_string(mode), "entries" => entries}
  end

  @doc false
  @spec recovery_entries(Placement.t()) :: [map()]
  def recovery_entries(%Placement{} = placement) do
    source_mapping_entries(placement.source_mappings, placement.job_id) ++
      destination_pair_entries(placement.destination_pairs, placement.job_id) ++
      lock_entry(placement, placement.job_id) ++
      owner_entry(placement, placement.job_id)
  end

  defp do_stage(placement, _channel, video, policy, opts) do
    ops = file_ops(opts)

    case acquire_lock(placement, ops) do
      {:ok, locked_placement} ->
        case stage_destination_files(locked_placement, video, policy, opts) do
          {:ok, staged_placement} ->
            case probe_staged_media(staged_placement, opts) do
              {:ok, verified_placement} ->
                case promote_destination_files(verified_placement, ops) do
                  {:ok, promoted_placement} ->
                    case quarantine_sources(promoted_placement, ops) do
                      {:ok, quarantined_placement} ->
                        {:ok, quarantined_placement}

                      {:error, reason, partial_placement} ->
                        stage_failure(reason, partial_placement, opts)
                    end

                  {:error, reason, partial_placement} ->
                    stage_failure(reason, partial_placement, opts)
                end

              {:error, reason, partial_placement} ->
                stage_failure(reason, partial_placement, opts)
            end

          {:error, reason, partial_placement} ->
            stage_failure(reason, partial_placement, opts)
        end

      {:error, {:owned_lock, reason}, partial_placement} ->
        stage_failure(reason, partial_placement, opts)

      {:error, reason, _unlocked_placement} ->
        {:error, normalize_stage_error(reason), []}
    end
  end

  defp probe_staged_media(placement, opts) do
    media_pair = Enum.find(placement.destination_pairs, &(&1.kind == :media))

    case probe(opts).probe(media_pair.marker_path, probe_timeout(opts)) do
      {:ok, result} -> {:ok, %{placement | quality: Map.get(result, :quality)}}
      {:error, reason} -> {:error, reason, placement}
    end
  end

  defp stage_failure(reason, placement, opts) do
    reason = normalize_stage_error(reason)

    case rollback(placement, opts) do
      {:ok, []} -> {:error, reason, []}
      {:error, entries} -> {:error, reason, entries}
    end
  end

  defp initial_placement(job_id, manifest) do
    destination_pairs = destination_pairs(manifest, job_id)
    source_directory = Path.dirname(manifest.source.source_path)
    quarantine_directory = Path.join(source_directory, ".ytdarr-import-#{job_id}")

    %Placement{
      job_id: job_id,
      manifest: manifest,
      lock_path: lock_path(manifest.destination),
      lock_fingerprint: nil,
      destination_pairs: destination_pairs,
      source_quarantine_directory: quarantine_directory,
      quarantine_owner_path: Path.join(quarantine_directory, ".owner"),
      quarantine_owner_fingerprint: nil,
      source_mappings: [],
      file_size: manifest.source.fingerprint.size,
      quality: manifest.quality
    }
  end

  defp destination_pairs(manifest, job_id) do
    media_pair = pair_for_artifact(manifest.source, job_id)

    sidecar_pairs =
      manifest
      |> selected_sidecars()
      |> Enum.map(&pair_for_artifact(&1, job_id))

    nfo_pair = %DestinationPair{
      id: :generated_nfo,
      kind: :nfo,
      marker_path: stage_marker_path(manifest.destination.nfo_path, job_id),
      final_path: manifest.destination.nfo_path,
      marker_fingerprint: nil,
      final_fingerprint: nil
    }

    [media_pair | sidecar_pairs] ++ [nfo_pair]
  end

  defp pair_for_artifact(%Artifact{} = artifact, job_id) do
    %DestinationPair{
      id: artifact.id,
      kind: artifact.kind,
      marker_path: stage_marker_path(artifact.destination_path, job_id),
      final_path: artifact.destination_path,
      marker_fingerprint: nil,
      final_fingerprint: nil
    }
  end

  defp stage_destination_files(placement, video, policy, opts) do
    manifest = placement.manifest

    Enum.reduce_while(placement.destination_pairs, {:ok, placement}, fn pair, {:ok, current} ->
      result =
        case pair.id do
          :generated_nfo ->
            stage_nfo_pair(current, pair, video, policy, opts)

          artifact_id ->
            stage_artifact_pair(
              current,
              pair,
              artifact_by_id(manifest, artifact_id),
              policy,
              opts
            )
        end

      case result do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, reason, updated} -> {:halt, {:error, reason, updated}}
      end
    end)
  end

  defp stage_artifact_pair(placement, pair, %Artifact{} = artifact, policy, opts) do
    ops = file_ops(opts)

    case create_marker(placement, pair, ops) do
      {:ok, created_placement} ->
        stage_copied_marker(created_placement, pair, artifact, policy, opts)

      {:error, reason, partial_placement} ->
        {:error, normalize_stage_error(reason), partial_placement}
    end
  end

  defp stage_copied_marker(placement, pair, artifact, policy, opts) do
    ops = file_ops(opts)

    with :ok <- ensure_artifact_unchanged(artifact, ops) do
      case normalize_op(ops_copy(ops, artifact.source_path, pair.marker_path)) do
        :ok ->
          case refresh_marker_fingerprint(placement, pair.id, ops) do
            {:ok, copied_placement} ->
              stage_touched_marker(copied_placement, pair, artifact, policy, opts)

            {:error, reason} ->
              {:error, normalize_stage_error(reason), placement}
          end

        {:error, reason} ->
          {:error, normalize_stage_error(reason), refreshed_or_original(placement, pair.id, ops)}
      end
    else
      {:error, reason} -> {:error, normalize_stage_error(reason), placement}
    end
  end

  defp stage_touched_marker(placement, pair, artifact, policy, opts) do
    ops = file_ops(opts)

    with :ok <- verify_staged_copy(pair.marker_path, artifact.fingerprint.size, ops),
         :ok <- permissions(opts).apply_file(pair.marker_path, policy),
         :ok <- normalize_op(ops_touch(ops, pair.marker_path, artifact.fingerprint.mtime)),
         {:ok, touched_placement} <- refresh_marker_fingerprint(placement, pair.id, ops) do
      {:ok, touched_placement}
    else
      {:error, reason} ->
        {:error, normalize_stage_error(reason), refreshed_or_original(placement, pair.id, ops)}
    end
  end

  defp stage_nfo_pair(placement, pair, video, policy, opts) do
    ops = file_ops(opts)

    case create_marker(placement, pair, ops) do
      {:ok, created_placement} ->
        case VideoArtifacts.write_nfo(
               pair.marker_path,
               video,
               created_placement.manifest.destination.episode_number,
               policy
             ) do
          :ok ->
            case refresh_marker_fingerprint(created_placement, pair.id, ops) do
              {:ok, written_placement} ->
                case permissions(opts).apply_file(pair.marker_path, policy) do
                  :ok -> {:ok, written_placement}
                  {:error, reason} -> {:error, normalize_stage_error(reason), written_placement}
                end

              {:error, reason} ->
                {:error, normalize_stage_error(reason), created_placement}
            end

          {:error, reason} ->
            {:error, normalize_stage_error(reason),
             refreshed_or_original(created_placement, pair.id, ops)}
        end

      {:error, reason, partial_placement} ->
        {:error, normalize_stage_error(reason), partial_placement}
    end
  end

  defp refreshed_or_original(placement, pair_id, ops) do
    case refresh_marker_fingerprint(placement, pair_id, ops) do
      {:ok, refreshed_placement} -> refreshed_placement
      {:error, _reason} -> placement
    end
  end

  defp create_marker(placement, pair, ops) do
    case ops_create_exclusive(ops, pair.marker_path, <<>>) do
      :ok ->
        case fingerprint_path(pair.marker_path, ops) do
          {:ok, fingerprint} ->
            {:ok, update_pair(placement, pair.id, &%{&1 | marker_fingerprint: fingerprint})}

          {:error, reason} ->
            {:error, {:stage_marker, reason}, placement}
        end

      {:error, :eexist} ->
        {:error, :destination_exists, placement}

      {:error, reason} ->
        {:error, {:stage_marker, reason}, placement}
    end
  end

  defp refresh_marker_fingerprint(placement, pair_id, ops) do
    pair = find_pair!(placement, pair_id)

    case fingerprint_path(pair.marker_path, ops) do
      {:ok, fingerprint} ->
        {:ok, update_pair(placement, pair_id, &%{&1 | marker_fingerprint: fingerprint})}

      {:error, reason} ->
        {:error, {:stage_marker, reason}}
    end
  end

  defp verify_staged_copy(path, expected_size, ops) do
    case ops_lstat(ops, path) do
      {:ok, %{type: :regular, size: ^expected_size}} -> :ok
      {:ok, _stat} -> {:error, :staged_copy_changed}
      {:error, reason} -> {:error, {:staged_copy, reason}}
    end
  end

  defp promote_destination_files(placement, ops) do
    with :ok <- ensure_final_paths_available(placement.destination_pairs, ops),
         {:ok, promoted} <- promote_pairs(placement, ops) do
      {:ok, promoted}
    else
      {:error, reason, partial} -> {:error, reason, partial}
      {:error, reason} -> {:error, reason, placement}
    end
  end

  defp promote_pairs(placement, ops) do
    Enum.reduce_while(placement.destination_pairs, {:ok, placement}, fn pair, {:ok, current} ->
      case ops_hard_link(ops, pair.marker_path, pair.final_path) do
        :ok ->
          case promotion_fingerprints(pair, ops) do
            {:ok, marker_fingerprint, final_fingerprint} ->
              updated =
                update_pair(current, pair.id, fn destination_pair ->
                  %{
                    destination_pair
                    | marker_fingerprint: marker_fingerprint,
                      final_fingerprint: final_fingerprint
                  }
                end)

              {:cont, {:ok, updated}}

            {:error, reason} ->
              {:halt, {:error, reason, current}}
          end

        {:error, :eexist} ->
          {:halt, {:error, :destination_exists, current}}

        {:error, reason} ->
          {:halt, {:error, hard_link_error(reason), current}}
      end
    end)
  end

  defp promotion_fingerprints(pair, ops) do
    with {:ok, marker_fingerprint} <- fingerprint_path(pair.marker_path, ops),
         {:ok, final_fingerprint} <- fingerprint_path(pair.final_path, ops),
         true <- same_inode?(marker_fingerprint, final_fingerprint) do
      {:ok, marker_fingerprint, final_fingerprint}
    else
      false -> {:error, :promotion_mismatch}
      {:error, reason} -> {:error, {:promotion, reason}}
    end
  end

  defp quarantine_sources(placement, ops) do
    with {:ok, placement} <- create_quarantine_directory(placement, ops),
         {:ok, placement} <- create_quarantine_owner(placement, ops) do
      move_source_artifacts(placement, ops)
    else
      {:error, reason, partial_placement} -> {:error, reason, partial_placement}
    end
  end

  defp create_quarantine_directory(placement, ops) do
    case ops_mkdir(ops, placement.source_quarantine_directory) do
      :ok -> {:ok, placement}
      {:error, :eexist} -> {:error, :import_conflict, placement}
      {:error, :eacces} -> {:error, :source_not_writable, placement}
      {:error, reason} -> {:error, {:source_quarantine, reason}, placement}
    end
  end

  defp create_quarantine_owner(placement, ops) do
    case ops_create_exclusive(
           ops,
           placement.quarantine_owner_path,
           Integer.to_string(placement.job_id)
         ) do
      :ok ->
        case fingerprint_path(placement.quarantine_owner_path, ops) do
          {:ok, fingerprint} -> {:ok, %{placement | quarantine_owner_fingerprint: fingerprint}}
          {:error, reason} -> {:error, {:quarantine_owner, reason}, placement}
        end

      {:error, reason} ->
        {:error, {:quarantine_owner, reason}, placement}
    end
  end

  defp move_source_artifacts(placement, ops) do
    source_artifacts = source_artifacts_to_quarantine(placement.manifest)

    Enum.reduce_while(source_artifacts, {:ok, placement}, fn artifact, {:ok, current} ->
      quarantine_path =
        Path.join(current.source_quarantine_directory, Path.basename(artifact.source_path))

      case move_one_source_artifact(current, artifact, quarantine_path, ops) do
        {:ok, updated_placement} ->
          {:cont, {:ok, updated_placement}}

        {:error, reason, partial_placement} ->
          {:halt, {:error, normalize_quarantine_error(reason), partial_placement}}
      end
    end)
  end

  defp move_one_source_artifact(placement, artifact, quarantine_path, ops) do
    with :ok <- ensure_artifact_unchanged(artifact, ops),
         :ok <- ensure_path_absent(quarantine_path, ops) do
      case ops_rename(ops, artifact.source_path, quarantine_path) do
        :ok ->
          {:ok, append_quarantine_mapping(placement, artifact, quarantine_path, ops)}

        {:error, reason} ->
          {:error, reason, append_if_quarantined(placement, artifact, quarantine_path, ops)}
      end
    else
      {:error, reason} -> {:error, reason, placement}
    end
  end

  defp append_if_quarantined(placement, artifact, quarantine_path, ops) do
    case {fingerprint_path(quarantine_path, ops), ops_lstat(ops, artifact.source_path)} do
      {{:ok, fingerprint}, {:error, :enoent}} when fingerprint == artifact.fingerprint ->
        append_quarantine_mapping(placement, artifact, quarantine_path, ops)

      _ ->
        placement
    end
  end

  defp append_quarantine_mapping(placement, artifact, quarantine_path, ops) do
    fingerprint =
      case fingerprint_path(quarantine_path, ops) do
        {:ok, current_fingerprint} -> current_fingerprint
        {:error, _reason} -> artifact.fingerprint
      end

    mapping = %SourceMapping{
      kind: artifact.kind,
      original_path: artifact.source_path,
      quarantine_path: quarantine_path,
      fingerprint: fingerprint
    }

    %{placement | source_mappings: placement.source_mappings ++ [mapping]}
  end

  defp acquire_lock(placement, ops) do
    case ops_create_exclusive(ops, placement.lock_path, Integer.to_string(placement.job_id)) do
      :ok ->
        case fingerprint_path(placement.lock_path, ops) do
          {:ok, fingerprint} -> {:ok, %{placement | lock_fingerprint: fingerprint}}
          {:error, reason} -> {:error, {:owned_lock, reason}, placement}
        end

      {:error, :eexist} ->
        {:error, :import_conflict, placement}

      {:error, :eacces} ->
        {:error, :source_not_writable, placement}

      {:error, reason} ->
        {:error, {:lock, reason}, placement}
    end
  end

  defp validate_manifest(%Manifest{} = manifest) do
    case Manifest.from_map(Manifest.to_map(manifest)) do
      {:ok, _manifest} -> :ok
      {:error, _reason} -> {:error, :source_changed}
    end
  end

  defp validate_stage_identity(manifest, channel, video) do
    if manifest.video_id == Map.get(video, :id) and manifest.channel_id == Map.get(channel, :id) do
      :ok
    else
      {:error, :source_changed}
    end
  end

  defp validate_stale_preview(manifest, channel, video, ops) do
    source_path = manifest.source.source_path

    with {:ok, source} <- source_artifact(source_path, ops),
         {:ok, destination} <-
           VideoArtifacts.build_destination(channel, video, Path.extname(source_path)),
         :ok <- ensure_destination_matches(destination, manifest.destination),
         source = %{source | destination_path: destination.media_path},
         true <- immutable_artifact?(source, manifest.source),
         {:ok, sidecars, source_nfo} <- discover_companions(source, destination, ops),
         true <- immutable_artifacts?(sidecars, manifest.sidecars),
         true <- nullable_artifact_equal?(source_nfo, manifest.source_nfo),
         :ok <- ensure_initial_destination_available(destination, ops) do
      :ok
    else
      false -> {:error, :source_changed}
      {:error, :destination_exists} -> {:error, :destination_exists}
      {:error, :import_conflict} -> {:error, :import_conflict}
      {:error, :missing_upload_date} -> {:error, :destination_changed}
      {:error, :enoent} -> {:error, :source_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_destination_matches(destination, destination), do: :ok

  defp ensure_destination_matches(_destination, _expected_destination),
    do: {:error, :destination_changed}

  defp source_artifact(path, ops) do
    with {:ok, stat} <- ops_lstat(ops, path),
         :regular <- Map.get(stat, :type) do
      {:ok,
       %Artifact{
         id: opaque_id(),
         kind: :media,
         source_path: path,
         destination_path: nil,
         fingerprint: Fingerprint.from_stat(stat)
       }}
    else
      {:ok, _stat} -> {:error, :video_not_importable}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :video_not_importable}
    end
  end

  defp ensure_video_extension(path) do
    if MapSet.member?(@video_extensions, path |> Path.extname() |> String.downcase()) do
      :ok
    else
      {:error, :video_not_importable}
    end
  end

  defp ensure_readable(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io_device} ->
        File.close(io_device)
        :ok

      {:error, :enoent} ->
        {:error, :source_unavailable}

      {:error, _reason} ->
        {:error, :source_unreadable}
    end
  end

  defp ensure_source_directory_writable(directory, ops) do
    probe_path = Path.join(directory, ".ytdarr-import-probe-#{opaque_id()}")

    case ops_create_exclusive(ops, probe_path, <<>>) do
      :ok ->
        case ops_remove(ops, probe_path) do
          :ok -> :ok
          {:error, _reason} -> {:error, :source_not_writable}
        end

      {:error, _reason} ->
        {:error, :source_not_writable}
    end
  end

  defp discover_companions(%Artifact{} = source, %Destination{} = destination, ops) do
    directory = Path.dirname(source.source_path)
    stem = source.source_path |> Path.basename() |> Path.rootname()

    with {:ok, names} <- ops_list(ops, directory) do
      names
      |> Enum.reduce_while({:ok, [], nil}, fn name, {:ok, sidecars, source_nfo} ->
        path = Path.join(directory, name)

        case companion_kind(name, stem) do
          nil ->
            {:cont, {:ok, sidecars, source_nfo}}

          kind ->
            case companion_artifact(path, name, stem, destination, kind, ops) do
              {:ok, nil} -> {:cont, {:ok, sidecars, source_nfo}}
              {:ok, %Artifact{kind: :source_nfo} = artifact} -> {:cont, {:ok, sidecars, artifact}}
              {:ok, artifact} -> {:cont, {:ok, [artifact | sidecars], source_nfo}}
              {:error, :enoent} -> {:cont, {:ok, sidecars, source_nfo}}
              {:error, reason} -> {:halt, {:error, reason}}
            end
        end
      end)
      |> case do
        {:ok, sidecars, source_nfo} -> {:ok, Enum.sort_by(sidecars, & &1.source_path), source_nfo}
        error -> error
      end
    end
  end

  defp companion_kind(name, stem) do
    extension = name |> Path.extname() |> String.downcase()

    cond do
      name == stem <> ".nfo" -> :source_nfo
      exact_stem?(name, stem) and MapSet.member?(@artwork_extensions, extension) -> :artwork
      qualified_stem?(name, stem) and MapSet.member?(@subtitle_extensions, extension) -> :subtitle
      true -> nil
    end
  end

  defp companion_artifact(path, name, stem, destination, kind, ops) do
    case ops_lstat(ops, path) do
      {:ok, %{type: :regular} = stat} ->
        destination_path =
          case kind do
            :source_nfo -> nil
            _ -> replace_stem(destination.media_path, name, stem)
          end

        {:ok,
         %Artifact{
           id: opaque_id(),
           kind: kind,
           source_path: path,
           destination_path: destination_path,
           fingerprint: Fingerprint.from_stat(stat)
         }}

      {:ok, _non_regular} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp exact_stem?(name, stem), do: name == stem <> Path.extname(name)

  defp qualified_stem?(name, stem) do
    String.starts_with?(name, stem <> ".") and byte_size(name) > byte_size(stem) + 1
  end

  defp replace_stem(destination_media_path, source_name, source_stem) do
    destination_stem = Path.rootname(destination_media_path)
    suffix = String.replace_prefix(source_name, source_stem, "")
    destination_stem <> suffix
  end

  defp ensure_initial_destination_available(destination, ops) do
    with :ok <- ensure_paths_absent([destination.media_path, destination.nfo_path], ops) do
      case ensure_path_absent(lock_path(destination), ops) do
        :ok -> :ok
        {:error, :already_exists} -> {:error, :import_conflict}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :already_exists} -> {:error, :destination_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_selected_destination_available(manifest, ops) do
    paths = [
      manifest.destination.media_path,
      manifest.destination.nfo_path | Enum.map(selected_sidecars(manifest), & &1.destination_path)
    ]

    case ensure_paths_absent(paths, ops) do
      :ok -> :ok
      {:error, :already_exists} -> {:error, :destination_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_final_paths_available(pairs, ops) do
    case ensure_paths_absent(Enum.map(pairs, & &1.final_path), ops) do
      :ok -> :ok
      {:error, :already_exists} -> {:error, :destination_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_paths_absent(paths, ops) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case ensure_path_absent(path, ops) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp ensure_path_absent(path, ops) do
    case ops_lstat(ops, path) do
      {:error, :enoent} -> :ok
      {:ok, _stat} -> {:error, :already_exists}
      {:error, reason} -> {:error, reason}
    end
  end

  defp path_absent?(path, ops), do: match?({:error, :enoent}, ops_lstat(ops, path))

  defp selected_sidecars(manifest) do
    selected_ids = MapSet.new(manifest.selected_sidecar_ids)
    Enum.filter(manifest.sidecars, &MapSet.member?(selected_ids, &1.id))
  end

  defp source_artifacts_to_quarantine(manifest) do
    [manifest.source | selected_sidecars(manifest)] ++
      if(manifest.source_nfo, do: [manifest.source_nfo], else: [])
  end

  defp artifact_by_id(manifest, id) do
    if id == manifest.source.id do
      manifest.source
    else
      Enum.find(manifest.sidecars, &(&1.id == id))
    end
  end

  defp ensure_artifact_unchanged(%Artifact{} = artifact, ops) do
    case fingerprint_path(artifact.source_path, ops) do
      {:ok, fingerprint} when fingerprint == artifact.fingerprint -> :ok
      _ -> {:error, :source_changed}
    end
  end

  defp immutable_artifact?(%Artifact{} = left, %Artifact{} = right) do
    left.kind == right.kind and
      left.source_path == right.source_path and
      left.destination_path == right.destination_path and
      left.fingerprint == right.fingerprint
  end

  defp immutable_artifacts?(left, right) when is_list(left) and is_list(right) do
    left
    |> Enum.sort_by(& &1.source_path)
    |> Enum.zip(Enum.sort_by(right, & &1.source_path))
    |> then(fn pairs ->
      length(left) == length(right) and
        Enum.all?(pairs, fn {first, second} -> immutable_artifact?(first, second) end)
    end)
  end

  defp nullable_artifact_equal?(nil, nil), do: true

  defp nullable_artifact_equal?(%Artifact{} = left, %Artifact{} = right),
    do: immutable_artifact?(left, right)

  defp nullable_artifact_equal?(_left, _right), do: false

  defp update_pair(placement, pair_id, fun) do
    %{
      placement
      | destination_pairs:
          Enum.map(placement.destination_pairs, fn pair ->
            if pair.id == pair_id, do: fun.(pair), else: pair
          end)
    }
  end

  defp find_pair!(placement, pair_id) do
    Enum.find(placement.destination_pairs, &(&1.id == pair_id)) ||
      raise ArgumentError, "unknown destination pair"
  end

  defp hard_link_error(reason) when reason in [:exdev, :enotsup, :eopnotsupp],
    do: :hard_link_unsupported

  defp hard_link_error(reason), do: {:hard_link, reason}

  defp normalize_inspection_error(:enoent), do: :source_unavailable
  defp normalize_inspection_error(:eacces), do: :source_unreadable
  defp normalize_inspection_error(reason), do: normalize_stage_error(reason)

  defp normalize_stage_error(reason)
       when reason in [
              :ffprobe_unavailable,
              :ffprobe_timeout,
              :ffprobe_output_too_large,
              :ffprobe_malformed_output,
              :ffprobe_failed,
              :no_video_stream,
              :video_not_importable,
              :missing_upload_date,
              :source_unavailable,
              :source_changed,
              :destination_changed,
              :destination_exists,
              :invalid_sidecar_selection,
              :import_conflict,
              :source_unreadable,
              :source_not_writable,
              :hard_link_unsupported
            ],
       do: reason

  defp normalize_stage_error(:eacces), do: :source_not_writable
  defp normalize_stage_error({_, :eacces}), do: :source_not_writable
  defp normalize_stage_error(_reason), do: :video_not_importable

  defp normalize_quarantine_error(:already_exists), do: :import_conflict
  defp normalize_quarantine_error(reason), do: normalize_stage_error(reason)

  defp normalize_op(:ok), do: :ok
  defp normalize_op({:ok, _value}), do: :ok
  defp normalize_op({:error, reason}), do: {:error, reason}
  defp normalize_op(other), do: {:error, other}

  defp rollback_source_mappings(mappings, :owned, ops) do
    Enum.reduce(mappings, [], fn mapping, remaining ->
      case restore_source_mapping(mapping, ops) do
        :ok -> remaining
        :remaining -> [mapping | remaining]
      end
    end)
    |> Enum.reverse()
  end

  defp rollback_source_mappings(mappings, _owner_status, _ops), do: mappings

  defp restore_source_mapping(mapping, ops) do
    case fingerprint_path(mapping.quarantine_path, ops) do
      {:error, :enoent} ->
        :ok

      {:ok, fingerprint} when fingerprint == mapping.fingerprint ->
        restore_present_source_mapping(mapping, fingerprint, ops)

      _ ->
        :remaining
    end
  end

  defp restore_present_source_mapping(mapping, quarantine_fingerprint, ops) do
    case ops_lstat(ops, mapping.original_path) do
      {:error, :enoent} ->
        case ops_rename(ops, mapping.quarantine_path, mapping.original_path) do
          :ok ->
            :ok

          {:error, _reason} ->
            if(mapping_restored?(mapping, quarantine_fingerprint, ops), do: :ok, else: :remaining)
        end

      {:ok, original_stat} ->
        if same_inode?(quarantine_fingerprint, Fingerprint.from_stat(original_stat)) do
          case ops_remove(ops, mapping.quarantine_path) do
            :ok ->
              :ok

            {:error, _reason} ->
              if(path_absent?(mapping.quarantine_path, ops), do: :ok, else: :remaining)
          end
        else
          :remaining
        end

      {:error, _reason} ->
        :remaining
    end
  end

  defp mapping_restored?(mapping, quarantine_fingerprint, ops) do
    match?({:error, :enoent}, ops_lstat(ops, mapping.quarantine_path)) and
      case fingerprint_path(mapping.original_path, ops) do
        {:ok, original_fingerprint} -> same_inode?(quarantine_fingerprint, original_fingerprint)
        _ -> false
      end
  end

  defp rollback_destination_pairs(pairs, ops) do
    Enum.reduce(pairs, [], fn pair, remaining ->
      case rollback_destination_pair(pair, ops) do
        :ok -> remaining
        :remaining -> [pair | remaining]
      end
    end)
    |> Enum.reverse()
  end

  defp rollback_destination_pair(pair, ops) do
    case owned_marker_fingerprint(pair, ops) do
      :absent ->
        :ok

      {:owned, marker_fingerprint} ->
        case ops_lstat(ops, pair.final_path) do
          {:error, :enoent} ->
            remove_marker(pair, ops)

          {:ok, final_stat} ->
            remove_proven_final(pair, marker_fingerprint, Fingerprint.from_stat(final_stat), ops)

          {:error, _reason} ->
            :remaining
        end

      :unowned ->
        :remaining
    end
  end

  defp remove_proven_final(pair, marker_fingerprint, final_fingerprint, ops) do
    if same_inode?(marker_fingerprint, final_fingerprint) do
      case ops_remove(ops, pair.final_path) do
        :ok ->
          remove_marker(pair, ops)

        {:error, _reason} ->
          if(path_absent?(pair.final_path, ops), do: remove_marker(pair, ops), else: :remaining)
      end
    else
      :remaining
    end
  end

  defp cleanup_destination_markers(pairs, ops) do
    Enum.reduce(pairs, [], fn pair, remaining ->
      case owned_marker_fingerprint(pair, ops) do
        :absent ->
          remaining

        {:owned, _fingerprint} ->
          if(remove_marker(pair, ops) == :ok, do: remaining, else: [pair | remaining])

        :unowned ->
          [pair | remaining]
      end
    end)
    |> Enum.reverse()
  end

  defp owned_marker_fingerprint(%DestinationPair{marker_fingerprint: nil} = pair, ops) do
    case ops_lstat(ops, pair.marker_path) do
      {:error, :enoent} -> :absent
      _ -> :unowned
    end
  end

  defp owned_marker_fingerprint(pair, ops) do
    case fingerprint_path(pair.marker_path, ops) do
      {:error, :enoent} -> :absent
      {:ok, fingerprint} when fingerprint == pair.marker_fingerprint -> {:owned, fingerprint}
      _ -> :unowned
    end
  end

  defp remove_marker(pair, ops) do
    case ops_remove(ops, pair.marker_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} -> if(path_absent?(pair.marker_path, ops), do: :ok, else: :remaining)
    end
  end

  defp cleanup_quarantined_sources(mappings, :owned, ops) do
    Enum.reduce(mappings, [], fn mapping, remaining ->
      case fingerprint_path(mapping.quarantine_path, ops) do
        {:error, :enoent} ->
          remaining

        {:ok, fingerprint} when fingerprint == mapping.fingerprint ->
          case ops_remove(ops, mapping.quarantine_path) do
            :ok ->
              remaining

            {:error, _reason} ->
              if(path_absent?(mapping.quarantine_path, ops),
                do: remaining,
                else: [mapping | remaining]
              )
          end

        _ ->
          [mapping | remaining]
      end
    end)
    |> Enum.reverse()
  end

  defp cleanup_quarantined_sources(mappings, _owner_status, _ops), do: mappings

  defp quarantine_owner_status(%Placement{quarantine_owner_path: nil}, _ops), do: :absent

  defp quarantine_owner_status(placement, ops) do
    case fingerprint_path(placement.quarantine_owner_path, ops) do
      {:error, :enoent} ->
        :absent

      {:ok, fingerprint} ->
        if owned_owner_file?(
             placement.quarantine_owner_path,
             placement.job_id,
             placement.quarantine_owner_fingerprint,
             fingerprint
           ) do
          :owned
        else
          :unowned
        end

      {:error, _reason} ->
        :unowned
    end
  end

  defp cleanup_lock(%Placement{lock_path: nil}, _ops), do: nil

  defp cleanup_lock(placement, ops) do
    case fingerprint_path(placement.lock_path, ops) do
      {:error, :enoent} ->
        nil

      {:ok, fingerprint} ->
        if owned_owner_file?(
             placement.lock_path,
             placement.job_id,
             placement.lock_fingerprint,
             fingerprint
           ) do
          case ops_remove(ops, placement.lock_path) do
            :ok ->
              nil

            {:error, :enoent} ->
              nil

            {:error, _reason} ->
              if(path_absent?(placement.lock_path, ops),
                do: nil,
                else: %{placement | lock_fingerprint: fingerprint}
              )
          end
        else
          %{placement | lock_fingerprint: fingerprint}
        end

      {:error, _reason} ->
        placement
    end
  end

  defp cleanup_quarantine_owner(%Placement{quarantine_owner_path: nil}, _mappings, _status, _ops),
    do: nil

  defp cleanup_quarantine_owner(placement, [_ | _], _status, _ops), do: placement
  defp cleanup_quarantine_owner(_placement, [], :absent, _ops), do: nil
  defp cleanup_quarantine_owner(placement, [], :unowned, _ops), do: placement

  defp cleanup_quarantine_owner(placement, [], :owned, ops) do
    case ops_list(ops, placement.source_quarantine_directory) do
      {:ok, [".owner"]} ->
        remove_owner_and_directory(placement, ops)

      {:ok, []} ->
        # A previous partial cleanup may have already removed the owner. The
        # empty directory cannot be proven owned any longer, so leave it alone.
        nil

      {:ok, _entries} ->
        placement

      {:error, :enoent} ->
        nil

      {:error, _reason} ->
        placement
    end
  end

  defp remove_owner_and_directory(placement, ops) do
    case ops_remove(ops, placement.quarantine_owner_path) do
      :ok ->
        remove_owned_directory(placement, ops)

      {:error, :enoent} ->
        remove_owned_directory(placement, ops)

      {:error, _reason} ->
        if(path_absent?(placement.quarantine_owner_path, ops),
          do: remove_owned_directory(placement, ops),
          else: placement
        )
    end
  end

  defp remove_owned_directory(placement, ops) do
    case ops_remove_dir(ops, placement.source_quarantine_directory) do
      :ok -> nil
      {:error, :enoent} -> nil
      {:error, _reason} -> restore_owner_after_failed_directory_removal(placement, ops)
    end
  end

  defp restore_owner_after_failed_directory_removal(placement, ops) do
    case ops_create_exclusive(
           ops,
           placement.quarantine_owner_path,
           Integer.to_string(placement.job_id)
         ) do
      :ok ->
        case fingerprint_path(placement.quarantine_owner_path, ops) do
          {:ok, fingerprint} -> %{placement | quarantine_owner_fingerprint: fingerprint}
          _ -> placement
        end

      _ ->
        placement
    end
  end

  defp owned_owner_file?(path, job_id, expected_fingerprint, actual_fingerprint) do
    fingerprint_matches? =
      is_nil(expected_fingerprint) or expected_fingerprint == actual_fingerprint

    fingerprint_matches? and
      case File.read(path) do
        {:ok, contents} -> String.trim(contents) == Integer.to_string(job_id)
        {:error, _reason} -> false
      end
  end

  defp result_from_entries([]), do: {:ok, []}
  defp result_from_entries(entries), do: {:error, entries}

  defp source_mapping_entries(mappings, job_id) do
    Enum.map(mappings, fn mapping ->
      recovery_entry(
        "source_quarantine",
        mapping.quarantine_path,
        mapping.original_path,
        job_id,
        mapping.fingerprint
      )
    end)
  end

  defp destination_pair_entries(pairs, job_id) do
    Enum.map(pairs, fn pair ->
      recovery_entry(
        "destination_marker",
        pair.marker_path,
        pair.final_path,
        job_id,
        pair.marker_fingerprint
      )
    end)
  end

  defp lock_entry(%Placement{lock_path: nil}, _job_id), do: []
  defp lock_entry(nil, _job_id), do: []

  defp lock_entry(%Placement{} = placement, job_id) do
    [recovery_entry("lock", placement.lock_path, nil, job_id, placement.lock_fingerprint)]
  end

  defp owner_entry(%Placement{quarantine_owner_path: nil}, _job_id), do: []
  defp owner_entry(nil, _job_id), do: []

  defp owner_entry(%Placement{} = placement, job_id) do
    [
      recovery_entry(
        "quarantine_owner",
        placement.quarantine_owner_path,
        nil,
        job_id,
        placement.quarantine_owner_fingerprint
      )
    ]
  end

  defp recovery_entry(kind, path, original_path, job_id, fingerprint) do
    %{
      "kind" => kind,
      "path" => path,
      "original_path" => original_path,
      "owner_job_id" => job_id,
      "major_device" => fingerprint && fingerprint.major_device,
      "minor_device" => fingerprint && fingerprint.minor_device,
      "inode" => fingerprint && fingerprint.inode,
      "size" => fingerprint && fingerprint.size,
      "mtime" => fingerprint && fingerprint.mtime
    }
  end

  defp recover_persisted(%{"mode" => mode, "entries" => entries} = recovery, state, opts)
       when mode in ["restore", "delete"] and is_list(entries) do
    expected_mode = recovery_mode_for_state(state)

    with true <- mode == expected_mode,
         {:ok, placement} <- placement_from_recovery_entries(entries) do
      case mode do
        "restore" -> rollback(placement, opts)
        "delete" -> commit_cleanup(placement, opts)
      end
    else
      _ -> {:error, recovery_entries_or_empty(recovery)}
    end
  end

  defp recover_persisted(recovery, _state, _opts),
    do: {:error, recovery_entries_or_empty(recovery)}

  defp recover_from_manifest(job_id, manifest, state, opts)
       when is_integer(job_id) and job_id > 0 do
    with {:ok, manifest} <- manifest_struct(manifest),
         {:ok, placement} <- reconstructed_placement(job_id, manifest, file_ops(opts)) do
      case recovery_mode_for_state(state) do
        "restore" -> rollback(placement, opts)
        "delete" -> commit_cleanup(placement, opts)
        nil -> {:error, recovery_entries(placement)}
      end
    else
      _ -> {:error, []}
    end
  end

  defp recover_from_manifest(_job_id, _manifest, _state, _opts), do: {:error, []}

  defp manifest_struct(%Manifest{} = manifest), do: {:ok, manifest}
  defp manifest_struct(map) when is_map(map), do: Manifest.from_map(map)
  defp manifest_struct(_manifest), do: {:error, :invalid_manifest}

  defp reconstructed_placement(job_id, manifest, ops) do
    placement = initial_placement(job_id, manifest)

    pairs =
      Enum.map(placement.destination_pairs, fn pair ->
        %{
          pair
          | marker_fingerprint: optional_fingerprint(pair.marker_path, ops),
            final_fingerprint: optional_fingerprint(pair.final_path, ops)
        }
      end)

    mappings =
      manifest
      |> source_artifacts_to_quarantine()
      |> Enum.reduce([], fn artifact, acc ->
        quarantine_path =
          Path.join(placement.source_quarantine_directory, Path.basename(artifact.source_path))

        case fingerprint_path(quarantine_path, ops) do
          {:ok, fingerprint} when fingerprint == artifact.fingerprint ->
            [
              %SourceMapping{
                kind: artifact.kind,
                original_path: artifact.source_path,
                quarantine_path: quarantine_path,
                fingerprint: fingerprint
              }
              | acc
            ]

          _ ->
            acc
        end
      end)
      |> Enum.reverse()

    {:ok,
     %{
       placement
       | destination_pairs: pairs,
         source_mappings: mappings,
         lock_fingerprint: optional_fingerprint(placement.lock_path, ops),
         quarantine_owner_fingerprint: optional_fingerprint(placement.quarantine_owner_path, ops)
     }}
  end

  defp optional_fingerprint(path, ops) do
    case fingerprint_path(path, ops) do
      {:ok, fingerprint} -> fingerprint
      _ -> nil
    end
  end

  defp placement_from_recovery_entries(entries) do
    with {:ok, parsed_entries} <- parse_recovery_entries(entries),
         {:ok, job_id} <- common_owner_job_id(parsed_entries),
         :ok <- validate_recovery_ownership(parsed_entries, job_id) do
      source_mappings =
        for %{kind: "source_quarantine"} = entry <- parsed_entries do
          %SourceMapping{
            kind: :unknown,
            original_path: entry.original_path,
            quarantine_path: entry.path,
            fingerprint: entry.fingerprint
          }
        end

      destination_pairs =
        for %{kind: "destination_marker"} = entry <- parsed_entries do
          %DestinationPair{
            id: opaque_id(),
            kind: :unknown,
            marker_path: entry.path,
            final_path: entry.original_path,
            marker_fingerprint: entry.fingerprint,
            final_fingerprint: nil
          }
        end

      lock = Enum.find(parsed_entries, &(&1.kind == "lock"))
      owner = Enum.find(parsed_entries, &(&1.kind == "quarantine_owner"))
      source_directory = recovery_source_directory(source_mappings, owner)

      {:ok,
       %Placement{
         job_id: job_id,
         manifest: nil,
         lock_path: lock && lock.path,
         lock_fingerprint: lock && lock.fingerprint,
         destination_pairs: destination_pairs,
         source_quarantine_directory: source_directory,
         quarantine_owner_path: owner && owner.path,
         quarantine_owner_fingerprint: owner && owner.fingerprint,
         source_mappings: source_mappings,
         file_size: nil,
         quality: nil
       }}
    end
  end

  defp parse_recovery_entries(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, parsed} ->
      case parse_recovery_entry(entry) do
        {:ok, recovery_entry} -> {:cont, {:ok, [recovery_entry | parsed]}}
        {:error, _reason} -> {:halt, {:error, :invalid_recovery}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_recovery_entries(_entries), do: {:error, :invalid_recovery}

  defp parse_recovery_entry(entry) when is_map(entry) do
    with {:ok, kind} <- recovery_kind(Map.get(entry, "kind")),
         {:ok, path} <- recovery_absolute_path(Map.get(entry, "path")),
         {:ok, original_path} <- recovery_original_path(kind, Map.get(entry, "original_path")),
         {:ok, owner_job_id} <- recovery_owner_job_id(Map.get(entry, "owner_job_id")),
         {:ok, fingerprint} <- recovery_fingerprint(entry) do
      {:ok,
       %{
         kind: kind,
         path: path,
         original_path: original_path,
         owner_job_id: owner_job_id,
         fingerprint: fingerprint
       }}
    end
  end

  defp parse_recovery_entry(_entry), do: {:error, :invalid_recovery}

  defp recovery_kind(kind)
       when kind in ["source_quarantine", "destination_marker", "lock", "quarantine_owner"],
       do: {:ok, kind}

  defp recovery_kind(_kind), do: {:error, :invalid_recovery}

  defp recovery_absolute_path(path) when is_binary(path) do
    if Path.type(path) == :absolute, do: {:ok, path}, else: {:error, :invalid_recovery}
  end

  defp recovery_absolute_path(_path), do: {:error, :invalid_recovery}

  defp recovery_original_path(kind, nil) when kind in ["lock", "quarantine_owner"], do: {:ok, nil}

  defp recovery_original_path(kind, path)
       when kind in ["source_quarantine", "destination_marker"] and is_binary(path) do
    if Path.type(path) == :absolute, do: {:ok, path}, else: {:error, :invalid_recovery}
  end

  defp recovery_original_path(_kind, _path), do: {:error, :invalid_recovery}

  defp recovery_owner_job_id(job_id) when is_integer(job_id) and job_id > 0, do: {:ok, job_id}
  defp recovery_owner_job_id(_job_id), do: {:error, :invalid_recovery}

  defp recovery_fingerprint(entry) do
    values =
      for key <- ["major_device", "minor_device", "inode", "size", "mtime"],
          do: Map.get(entry, key)

    cond do
      Enum.all?(values, &is_nil/1) ->
        {:ok, nil}

      Enum.all?(values, &(is_integer(&1) and &1 >= 0)) ->
        {:ok,
         %Fingerprint{
           major_device: Enum.at(values, 0),
           minor_device: Enum.at(values, 1),
           inode: Enum.at(values, 2),
           size: Enum.at(values, 3),
           mtime: Enum.at(values, 4)
         }}

      true ->
        {:error, :invalid_recovery}
    end
  end

  defp common_owner_job_id([]), do: {:error, :invalid_recovery}

  defp common_owner_job_id(entries) do
    job_ids = entries |> Enum.map(& &1.owner_job_id) |> Enum.uniq()

    case job_ids do
      [job_id] -> {:ok, job_id}
      _ -> {:error, :invalid_recovery}
    end
  end

  defp validate_recovery_ownership(entries, job_id) do
    source_entries = Enum.filter(entries, &(&1.kind == "source_quarantine"))
    owner_entries = Enum.filter(entries, &(&1.kind == "quarantine_owner"))

    with true <- length(Enum.filter(entries, &(&1.kind == "lock"))) <= 1,
         true <- length(owner_entries) <= 1,
         true <- Enum.all?(entries, &recovery_path_matches_owner?(&1, job_id)),
         :ok <- validate_source_owner_entries(source_entries, owner_entries, job_id) do
      :ok
    else
      _ -> {:error, :invalid_recovery}
    end
  end

  defp recovery_path_matches_owner?(
         %{kind: "source_quarantine", path: path, original_path: original_path},
         job_id
       ) do
    Path.basename(Path.dirname(path)) == ".ytdarr-import-#{job_id}" and
      Path.basename(path) == Path.basename(original_path)
  end

  defp recovery_path_matches_owner?(
         %{kind: "destination_marker", path: path, original_path: final_path},
         job_id
       ) do
    Path.basename(path) == ".#{Path.basename(final_path)}.ytdarr-import-#{job_id}.stage"
  end

  defp recovery_path_matches_owner?(%{kind: "quarantine_owner", path: path}, job_id) do
    Path.basename(path) == ".owner" and
      Path.basename(Path.dirname(path)) == ".ytdarr-import-#{job_id}"
  end

  defp recovery_path_matches_owner?(%{kind: "lock", path: path}, _job_id) do
    basename = Path.basename(path)
    String.starts_with?(basename, ".") and String.ends_with?(basename, ".ytdarr-import.lock")
  end

  defp validate_source_owner_entries([], _owners, _job_id), do: :ok

  defp validate_source_owner_entries(source_entries, [%{path: owner_path}], _job_id) do
    directory = Path.dirname(owner_path)

    if Enum.all?(source_entries, &(Path.dirname(&1.path) == directory)) do
      :ok
    else
      {:error, :invalid_recovery}
    end
  end

  defp validate_source_owner_entries(_source_entries, _owners, _job_id),
    do: {:error, :invalid_recovery}

  defp recovery_source_directory([], nil), do: nil
  defp recovery_source_directory([], owner), do: Path.dirname(owner.path)
  defp recovery_source_directory([mapping | _], _owner), do: Path.dirname(mapping.quarantine_path)

  defp recovery_mode_for_state(state)
       when state in [:importing, :import_failed, "importing", "import_failed"],
       do: "restore"

  defp recovery_mode_for_state(state) when state in [:downloaded, "downloaded"], do: "delete"
  defp recovery_mode_for_state(_state), do: nil

  defp recovery_entries_or_empty(%{"entries" => entries}) when is_list(entries), do: entries
  defp recovery_entries_or_empty(_recovery), do: []

  defp lock_path(%Destination{} = destination) do
    Path.join(
      destination.season_directory,
      ".#{Path.basename(destination.media_path)}.ytdarr-import.lock"
    )
  end

  defp stage_marker_path(final_path, job_id) do
    Path.join(
      Path.dirname(final_path),
      ".#{Path.basename(final_path)}.ytdarr-import-#{job_id}.stage"
    )
  end

  defp same_inode?(%Fingerprint{} = left, %Fingerprint{} = right) do
    left.major_device == right.major_device and
      left.minor_device == right.minor_device and
      left.inode == right.inode
  end

  defp same_inode?(_left, _right), do: false

  defp fingerprint_path(path, ops) do
    with {:ok, %{type: :regular} = stat} <- ops_lstat(ops, path) do
      {:ok, Fingerprint.from_stat(stat)}
    else
      {:ok, _stat} -> {:error, :not_regular}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_policy(opts) do
    case Keyword.fetch(opts, :policy) do
      {:ok, policy} -> {:ok, policy}
      :error -> permissions(opts).load_policy()
    end
  end

  defp file_ops(opts) do
    case Keyword.get(opts, :file_ops, {FileOps.Real, nil}) do
      {module, context} when is_atom(module) -> {module, context}
      module when is_atom(module) -> {module, nil}
    end
  end

  defp permissions(opts), do: Keyword.get(opts, :permissions, MediaPermissions)
  defp probe(opts), do: Keyword.get(opts, :probe, Ffprobe)
  defp probe_timeout(opts), do: Keyword.get(opts, :probe_timeout, @probe_timeout)

  defp ops_lstat({module, context}, path), do: module.lstat(context, path)
  defp ops_list({module, context}, path), do: module.list(context, path)
  defp ops_mkdir({module, context}, path), do: module.mkdir(context, path)

  defp ops_create_exclusive({module, context}, path, contents),
    do: module.create_exclusive(context, path, contents)

  defp ops_copy({module, context}, source, destination),
    do: module.copy(context, source, destination)

  defp ops_hard_link({module, context}, source, destination),
    do: module.hard_link(context, source, destination)

  defp ops_rename({module, context}, source, destination),
    do: module.rename(context, source, destination)

  defp ops_remove({module, context}, path), do: module.remove(context, path)
  defp ops_remove_dir({module, context}, path), do: module.remove_dir(context, path)
  defp ops_touch({module, context}, path, time), do: module.touch(context, path, time)

  defp opaque_id do
    :crypto.strong_rand_bytes(18)
    |> Base.url_encode64(padding: false)
  end
end
