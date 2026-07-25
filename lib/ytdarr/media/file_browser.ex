defmodule Ytdarr.Media.FileBrowser do
  @moduledoc """
  Lists directories in the Ytdarr process filesystem without ever following
  symbolic links. The browser deliberately has no configured root: callers
  begin at `/` and retain the returned opaque entry ids in server state.
  """

  @video_extensions MapSet.new(
                      ~w(.mp4 .mkv .webm .mov .m4v .avi .mpg .mpeg .ts .m2ts .wmv .flv .ogv)
                    )
  @per_page 100

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:id, :name, :path, :kind, :size]
    defstruct @enforce_keys

    @type kind :: :directory | :video
    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            path: Path.t(),
            kind: kind(),
            size: non_neg_integer() | nil
          }
  end

  defmodule Page do
    @moduledoc false

    @enforce_keys [
      :path,
      :parent_path,
      :breadcrumbs,
      :entries,
      :page,
      :per_page,
      :total_entries,
      :total_pages,
      :query,
      :show_hidden?
    ]
    defstruct @enforce_keys

    @type breadcrumb :: %{label: String.t(), path: Path.t()}
    @type t :: %__MODULE__{
            path: Path.t(),
            parent_path: Path.t() | nil,
            breadcrumbs: [breadcrumb()],
            entries: [Entry.t()],
            page: pos_integer(),
            per_page: 100,
            total_entries: non_neg_integer(),
            total_pages: pos_integer(),
            query: String.t(),
            show_hidden?: boolean()
          }
  end

  @doc """
  Lists real directories and supported video files directly below `path`.

  The page size is intentionally fixed so a forged client parameter cannot
  make an arbitrary filesystem listing expensive.
  """
  @spec list(Path.t(), keyword()) :: {:ok, Page.t()} | {:error, term()}
  def list(path, opts \\ [])

  def list(path, opts) when is_binary(path) and is_list(opts) do
    path = Path.expand(path)
    query = normalize_query(Keyword.get(opts, :query, ""))
    show_hidden? = Keyword.get(opts, :show_hidden?, false) == true
    page = normalize_page(Keyword.get(opts, :page, 1))

    with :ok <- ensure_directory(path),
         {:ok, entries} <- list_entries(path, show_hidden?),
         filtered_entries <- filter_entries(entries, query),
         total_entries <- length(filtered_entries),
         total_pages <- max(1, ceil_div(total_entries, @per_page)),
         :ok <- ensure_page_in_range(page, total_pages) do
      {:ok,
       %Page{
         path: path,
         parent_path: parent_path(path),
         breadcrumbs: breadcrumbs(path),
         entries: page_entries(filtered_entries, page),
         page: page,
         per_page: @per_page,
         total_entries: total_entries,
         total_pages: total_pages,
         query: query,
         show_hidden?: show_hidden?
       }}
    end
  end

  def list(_path, _opts), do: {:error, :not_a_directory}

  @doc false
  @spec video_file?(Path.t()) :: boolean()
  def video_file?(path) when is_binary(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> then(&MapSet.member?(@video_extensions, &1))
  end

  @doc false
  @spec video_extensions() :: MapSet.t(String.t())
  def video_extensions, do: @video_extensions

  defp ensure_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} -> :ok
      {:ok, _} -> {:error, :not_a_directory}
      {:error, reason} -> {:error, directory_error(reason)}
    end
  end

  defp list_entries(path, show_hidden?) do
    case File.ls(path) do
      {:ok, names} ->
        names
        |> Enum.reduce_while({:ok, []}, fn name, {:ok, entries} ->
          entry_path = Path.join(path, name)

          case entry_for(name, entry_path, show_hidden?) do
            {:ok, nil} -> {:cont, {:ok, entries}}
            {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
            {:error, :enoent} -> {:cont, {:ok, entries}}
            {:error, :eacces} -> {:halt, {:error, :directory_not_readable}}
            {:error, _reason} -> {:cont, {:ok, entries}}
          end
        end)
        |> case do
          {:ok, entries} -> {:ok, Enum.sort_by(entries, &entry_sort_key/1)}
          error -> error
        end

      {:error, reason} ->
        {:error, directory_error(reason)}
    end
  end

  defp entry_for(name, path, false) when is_binary(name) do
    if String.starts_with?(name, "."), do: {:ok, nil}, else: entry_for(name, path, true)
  end

  defp entry_for(name, path, true) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        {:ok, %Entry{id: opaque_id(), name: name, path: path, kind: :directory, size: nil}}

      {:ok, %{type: :regular, size: size}} ->
        if video_file?(name) do
          {:ok, %Entry{id: opaque_id(), name: name, path: path, kind: :video, size: size}}
        else
          {:ok, nil}
        end

      {:ok, _other} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filter_entries(entries, ""), do: entries

  defp filter_entries(entries, query) do
    needle = String.downcase(query)
    Enum.filter(entries, &String.contains?(String.downcase(&1.name), needle))
  end

  defp entry_sort_key(%Entry{kind: kind, name: name}) do
    kind_rank = if kind == :directory, do: 0, else: 1
    {kind_rank, String.downcase(name), name}
  end

  defp page_entries(entries, page) do
    entries
    |> Enum.drop((page - 1) * @per_page)
    |> Enum.take(@per_page)
  end

  defp breadcrumbs("/"), do: [%{label: "/", path: "/"}]

  defp breadcrumbs(path) do
    relative_path = Path.relative_to(path, "/")

    relative_path
    |> Path.split()
    |> Enum.reduce({"/", [%{label: "/", path: "/"}]}, fn segment, {parent, crumbs} ->
      next_path = Path.join(parent, segment)
      {next_path, crumbs ++ [%{label: segment, path: next_path}]}
    end)
    |> elem(1)
  end

  defp parent_path("/"), do: nil
  defp parent_path(path), do: Path.dirname(path)

  defp normalize_query(query) when is_binary(query), do: query
  defp normalize_query(_query), do: ""

  defp normalize_page(page) when is_integer(page) and page > 0, do: page
  defp normalize_page(_page), do: 1

  defp ensure_page_in_range(page, total_pages) when page <= total_pages, do: :ok
  defp ensure_page_in_range(_page, _total_pages), do: {:error, :page_out_of_range}

  defp directory_error(:enoent), do: :directory_not_found
  defp directory_error(:eacces), do: :directory_not_readable
  defp directory_error(:enotdir), do: :not_a_directory
  defp directory_error(reason), do: reason

  defp ceil_div(0, _divisor), do: 0
  defp ceil_div(number, divisor), do: div(number + divisor - 1, divisor)

  defp opaque_id do
    :crypto.strong_rand_bytes(18)
    |> Base.url_encode64(padding: false)
  end
end
