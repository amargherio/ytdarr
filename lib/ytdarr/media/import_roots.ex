defmodule Ytdarr.Media.ImportRoots do
  @moduledoc """
  Restricts filesystem imports to explicitly configured source directories.

  A permitted path must remain below one configured root and every component
  from the filesystem root through the selected file must be a real directory
  (or, for the last component, the requested regular file). This deliberately
  rejects symlinked roots and ancestors instead of resolving links.
  """

  @type kind :: :directory | :regular

  @spec roots() :: [Path.t()]
  def roots do
    :ytdarr
    |> Application.get_env(:import_roots, [])
    |> Enum.filter(&(is_binary(&1) and absolute_path?(&1)))
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  @spec first() :: {:ok, Path.t()} | {:error, :no_import_roots}
  def first do
    case roots() do
      [root | _] -> {:ok, root}
      [] -> {:error, :no_import_roots}
    end
  end

  @spec validate_path(Path.t(), kind()) :: :ok | {:error, term()}
  def validate_path(path, kind) when kind in [:directory, :regular] do
    validate_path(path, kind, roots())
  end

  @doc false
  @spec validate_path(Path.t(), kind(), [Path.t()]) :: :ok | {:error, term()}
  def validate_path(path, kind, roots) when is_binary(path) and kind in [:directory, :regular] do
    roots = normalize_roots(roots)

    with [_ | _] <- roots,
         true <- absolute_path?(path),
         expanded_path <- Path.expand(path),
         true <- Enum.any?(roots, &within?(&1, expanded_path)),
         :ok <- ensure_real_ancestors(expanded_path, kind) do
      :ok
    else
      [] -> {:error, :no_import_roots}
      false -> {:error, :outside_import_roots}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_path(_path, _kind, _roots), do: {:error, :outside_import_roots}

  defp normalize_roots(roots) when is_list(roots) do
    roots
    |> Enum.filter(&(is_binary(&1) and absolute_path?(&1)))
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp normalize_roots(_roots), do: []
  defp absolute_path?(path), do: String.starts_with?(path, "/")

  defp within?(root, path) do
    root == "/" or path == root or String.starts_with?(path, root <> "/")
  end

  defp ensure_real_ancestors(path, kind) do
    path
    |> Path.split()
    |> Enum.reduce_while({:ok, "/"}, fn segment, {:ok, current} ->
      next = if segment == "/", do: "/", else: Path.join(current, segment)
      expected_kind = if next == path, do: kind, else: :directory

      case File.lstat(next) do
        {:ok, %{type: :symlink}} -> {:halt, {:error, :outside_import_roots}}
        {:ok, %{type: ^expected_kind}} -> {:cont, {:ok, next}}
        {:ok, _} -> {:halt, {:error, expected_path_error(expected_kind)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _path} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp expected_path_error(:directory), do: :not_a_directory
  defp expected_path_error(:regular), do: :not_regular
end
