defmodule Ytdarr.MediaPermissions do
  @moduledoc """
  Resolves and applies the runtime ownership and mode policy for media files.

  Group changes are limited to groups already available to the operating-system
  process. Recursive normalization never follows symbolic links.
  """

  import Ecto.Query, only: [from: 2]

  alias Ytdarr.{Repo, Settings}

  @error_limit 20
  @pubsub Ytdarr.PubSub
  @topic "media_permissions"
  @worker "Ytdarr.ObanWorkers.MediaPermissionsWorker"

  defmodule Policy do
    @moduledoc false

    @enforce_keys [
      :owner_group,
      :gid,
      :file_mode,
      :file_mode_value,
      :directory_mode,
      :directory_mode_value
    ]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            owner_group: String.t(),
            gid: non_neg_integer(),
            file_mode: String.t(),
            file_mode_value: non_neg_integer(),
            directory_mode: String.t(),
            directory_mode_value: non_neg_integer()
          }
  end

  @type summary :: %{
          files: non_neg_integer(),
          directories: non_neg_integer(),
          skipped: non_neg_integer(),
          failed: non_neg_integer(),
          errors: [map()]
        }

  @doc "Loads and validates the effective media permission settings."
  @spec load_policy(keyword()) :: {:ok, Policy.t()} | {:error, term()}
  def load_policy(opts \\ []) do
    media = Settings.effective_config().media

    build_policy(
      %{
        owner_group: media.owner_group,
        file_mode: media.file_mode,
        directory_mode: media.directory_mode
      },
      opts
    )
  end

  @doc "Rebuilds and validates a policy captured in Oban job arguments."
  @spec policy_from_args(map(), keyword()) :: {:ok, Policy.t()} | {:error, term()}
  def policy_from_args(args, opts \\ [])

  def policy_from_args(
        %{
          "owner_group" => owner_group,
          "gid" => gid,
          "file_mode" => file_mode,
          "directory_mode" => directory_mode
        },
        opts
      )
      when is_integer(gid) do
    build_policy(
      %{owner_group: owner_group, file_mode: file_mode, directory_mode: directory_mode},
      Keyword.merge(opts,
        group_resolver: fn ^owner_group -> {:ok, gid} end
      )
    )
  end

  def policy_from_args(_args, _opts), do: {:error, :invalid_policy_snapshot}

  @doc "Converts a validated policy into JSON-safe Oban job arguments."
  @spec policy_args(Policy.t()) :: map()
  def policy_args(%Policy{} = policy) do
    %{
      "owner_group" => policy.owner_group,
      "gid" => policy.gid,
      "file_mode" => policy.file_mode,
      "directory_mode" => policy.directory_mode
    }
  end

  @doc "Queues normalization of all configured media roots using the current policy."
  @spec enqueue_existing_media() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_existing_media do
    with {:ok, policy} <- load_policy() do
      policy
      |> policy_args()
      |> Ytdarr.ObanWorkers.MediaPermissionsWorker.new()
      |> Oban.insert()
    end
  end

  @doc "Returns the newest persisted media-permissions job, if any."
  @spec latest_job() :: Oban.Job.t() | nil
  def latest_job do
    from(job in Oban.Job,
      where: job.worker == @worker,
      order_by: [desc: job.inserted_at, desc: job.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "Returns whether an equivalent policy is already queued or executing."
  @spec policy_active?(Policy.t()) :: boolean()
  def policy_active?(%Policy{} = policy) do
    args = policy_args(policy)

    from(job in Oban.Job,
      where:
        job.worker == @worker and job.args == ^args and
          job.state in ["available", "scheduled", "executing", "retryable", "suspended"],
      select: count(job.id)
    )
    |> Repo.one()
    |> Kernel.>(0)
  end

  @doc "Subscribes the current process to permission-job completion events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc false
  def broadcast(event), do: Phoenix.PubSub.broadcast(@pubsub, @topic, event)

  @doc "Builds a validated policy from user-facing setting values."
  @spec build_policy(map(), keyword()) :: {:ok, Policy.t()} | {:error, term()}
  def build_policy(attrs, opts \\ []) when is_map(attrs) do
    owner_group = fetch_value(attrs, :owner_group)
    file_mode = fetch_value(attrs, :file_mode)
    directory_mode = fetch_value(attrs, :directory_mode)

    with {:ok, normalized_group} <- normalize_group(owner_group),
         {:ok, normalized_file_mode, file_mode_value} <- normalize_mode(:file_mode, file_mode),
         {:ok, normalized_directory_mode, directory_mode_value} <-
           normalize_mode(:directory_mode, directory_mode),
         {:ok, gid} <- resolve_group(normalized_group, opts),
         :ok <- ensure_group_membership(normalized_group, gid, opts) do
      {:ok,
       %Policy{
         owner_group: normalized_group,
         gid: gid,
         file_mode: normalized_file_mode,
         file_mode_value: file_mode_value,
         directory_mode: normalized_directory_mode,
         directory_mode_value: directory_mode_value
       }}
    end
  end

  @doc "Creates a directory tree and normalizes the target directory."
  @spec mkdir_p(Path.t(), Policy.t()) :: :ok | {:error, term()}
  def mkdir_p(path, %Policy{} = policy) do
    with :ok <- File.mkdir_p(path),
         :ok <- apply_directory(path, policy) do
      :ok
    end
  end

  @doc "Writes a regular file and applies the configured group and file mode."
  @spec write_file(Path.t(), iodata(), Policy.t()) :: :ok | {:error, term()}
  def write_file(path, contents, %Policy{} = policy) do
    with :ok <- File.write(path, contents),
         :ok <- apply_file(path, policy) do
      :ok
    end
  end

  @doc "Applies the configured group and file mode to a regular file."
  @spec apply_file(Path.t(), Policy.t()) :: :ok | {:error, term()}
  def apply_file(path, %Policy{} = policy) do
    apply_path(path, :regular, policy.gid, policy.file_mode_value)
  end

  @doc "Applies the configured group and directory mode to a directory."
  @spec apply_directory(Path.t(), Policy.t()) :: :ok | {:error, term()}
  def apply_directory(path, %Policy{} = policy) do
    apply_path(path, :directory, policy.gid, policy.directory_mode_value)
  end

  @doc "Normalizes regular files sharing the completed download's basename."
  @spec apply_download_artifacts(Path.t(), Policy.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def apply_download_artifacts(output_path, %Policy{} = policy) do
    directory = Path.dirname(output_path)
    prefix = Path.rootname(Path.basename(output_path)) <> "."

    with {:ok, entries} <- File.ls(directory) do
      entries
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.reduce_while({:ok, 0}, fn entry, {:ok, count} ->
        path = Path.join(directory, entry)

        case File.lstat(path) do
          {:ok, %{type: :regular}} ->
            case apply_file(path, policy) do
              :ok -> {:cont, {:ok, count + 1}}
              {:error, reason} -> {:halt, {:error, {:apply_permissions, path, reason}}}
            end

          {:ok, _stat} ->
            {:cont, {:ok, count}}

          {:error, reason} ->
            {:halt, {:error, {:lstat, path, reason}}}
        end
      end)
    end
  end

  @doc "Recursively normalizes a media root without following symbolic links."
  @spec normalize_tree(Path.t(), Policy.t()) :: {:ok, summary()} | {:error, term()}
  def normalize_tree(root, %Policy{} = policy) do
    case File.lstat(root) do
      {:ok, %{type: :directory}} -> {:ok, walk(root, policy, empty_summary())}
      {:ok, %{type: type}} -> {:error, {:invalid_root_type, root, type}}
      {:error, reason} -> {:error, {:lstat, root, reason}}
    end
  end

  @doc "Returns a concise user-facing description of a validation error."
  @spec error_message(term()) :: String.t()
  def error_message({:invalid_group, _value}), do: "Enter a valid POSIX group name."
  def error_message({:group_not_found, group}), do: "Group #{group} does not exist on this host."

  def error_message({:group_not_available, group}) do
    "Ytdarr is not a member of group #{group}. Add the service user to the group and restart Ytdarr."
  end

  def error_message({:group_lookup_unavailable, command}),
    do: "Cannot validate media groups because #{command} is unavailable."

  def error_message({:invalid_mode, :file_mode, _value}),
    do: "File mode must contain three octal digits, optionally prefixed with 0."

  def error_message({:invalid_mode, :directory_mode, _value}),
    do: "Directory mode must contain three octal digits, optionally prefixed with 0."

  def error_message(reason), do: "Unable to apply media permissions: #{inspect(reason)}"

  @doc false
  def merge_summaries(left, right) do
    %{
      files: left.files + right.files,
      directories: left.directories + right.directories,
      skipped: left.skipped + right.skipped,
      failed: left.failed + right.failed,
      errors: Enum.take(left.errors ++ right.errors, @error_limit)
    }
  end

  @doc false
  def empty_summary do
    %{files: 0, directories: 0, skipped: 0, failed: 0, errors: []}
  end

  defp fetch_value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp normalize_group(value) when is_binary(value) do
    group = String.trim(value)

    if byte_size(group) <= 255 and Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.-]*\$?$/, group) do
      {:ok, group}
    else
      {:error, {:invalid_group, value}}
    end
  end

  defp normalize_group(value), do: {:error, {:invalid_group, value}}

  defp normalize_mode(field, value) when is_binary(value) do
    mode = String.trim(value)

    normalized =
      case mode do
        <<a, b, c>> when a in ?0..?7 and b in ?0..?7 and c in ?0..?7 -> "0" <> mode
        <<?0, a, b, c>> when a in ?0..?7 and b in ?0..?7 and c in ?0..?7 -> mode
        _ -> nil
      end

    case normalized do
      nil -> {:error, {:invalid_mode, field, value}}
      valid -> {:ok, valid, String.to_integer(valid, 8)}
    end
  end

  defp normalize_mode(field, value), do: {:error, {:invalid_mode, field, value}}

  defp resolve_group(group, opts) do
    case Keyword.fetch(opts, :group_resolver) do
      {:ok, resolver} -> resolver.(group)
      :error -> resolve_system_group(group)
    end
  end

  defp resolve_system_group(group) do
    with executable when is_binary(executable) <- System.find_executable("getent"),
         {output, 0} <- System.cmd(executable, ["group", group], stderr_to_stdout: true),
         [_name, _password, gid_text, _members] <-
           String.split(String.trim(output), ":", parts: 4),
         {gid, ""} <- Integer.parse(gid_text) do
      {:ok, gid}
    else
      nil -> {:error, {:group_lookup_unavailable, "getent"}}
      {_output, _status} -> {:error, {:group_not_found, group}}
      _other -> {:error, {:group_not_found, group}}
    end
  end

  defp ensure_group_membership(group, gid, opts) do
    with {:ok, gids} <- current_group_ids(opts) do
      if gid in gids, do: :ok, else: {:error, {:group_not_available, group}}
    end
  end

  defp current_group_ids(opts) do
    case Keyword.fetch(opts, :current_gids) do
      {:ok, gids} when is_list(gids) -> {:ok, gids}
      :error -> system_group_ids()
    end
  end

  defp system_group_ids do
    with executable when is_binary(executable) <- System.find_executable("id"),
         {output, 0} <- System.cmd(executable, ["-G"], stderr_to_stdout: true) do
      gids =
        output
        |> String.split()
        |> Enum.map(&String.to_integer/1)

      {:ok, gids}
    else
      nil -> {:error, {:group_lookup_unavailable, "id"}}
      {_output, _status} -> {:error, {:group_lookup_unavailable, "id"}}
    end
  end

  defp apply_path(path, expected_type, gid, mode) do
    with {:ok, %{type: ^expected_type}} <- File.lstat(path),
         :ok <- :file.change_group(path, gid),
         :ok <- File.chmod(path, mode) do
      :ok
    else
      {:ok, %{type: type}} -> {:error, {:unexpected_type, type}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp walk(path, policy, summary) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} -> walk_directory(path, policy, summary)
      {:ok, %{type: :regular}} -> apply_and_count(path, :file, policy, summary)
      {:ok, %{type: type}} -> increment_skipped(summary, path, type)
      {:error, reason} -> record_error(summary, path, :lstat, reason)
    end
  end

  defp walk_directory(path, policy, summary) do
    summary =
      case File.ls(path) do
        {:ok, entries} ->
          Enum.reduce(entries, summary, fn entry, acc ->
            walk(Path.join(path, entry), policy, acc)
          end)

        {:error, reason} ->
          record_error(summary, path, :list_directory, reason)
      end

    apply_and_count(path, :directory, policy, summary)
  end

  defp apply_and_count(path, :file, policy, summary) do
    case apply_file(path, policy) do
      :ok -> Map.update!(summary, :files, &(&1 + 1))
      {:error, reason} -> record_error(summary, path, :apply_file, reason)
    end
  end

  defp apply_and_count(path, :directory, policy, summary) do
    case apply_directory(path, policy) do
      :ok -> Map.update!(summary, :directories, &(&1 + 1))
      {:error, reason} -> record_error(summary, path, :apply_directory, reason)
    end
  end

  defp increment_skipped(summary, _path, _type), do: Map.update!(summary, :skipped, &(&1 + 1))

  defp record_error(summary, path, operation, reason) do
    errors =
      if length(summary.errors) < @error_limit do
        [%{path: path, operation: operation, reason: reason} | summary.errors]
      else
        summary.errors
      end

    %{summary | failed: summary.failed + 1, errors: errors}
  end
end
