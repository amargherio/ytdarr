defmodule Ytdarr.Media.FileBrowserTest do
  use ExUnit.Case, async: false

  alias Ytdarr.Media.FileBrowser

  setup do
    root =
      Path.join(System.tmp_dir!(), "ytdarr-file-browser-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "lists / with an absolute root breadcrumb" do
    assert {:ok, page} = FileBrowser.list("/")
    assert [%{label: "/", path: "/"} | _] = page.breadcrumbs
    assert page.path == "/"
    assert page.parent_path == nil
    assert page.per_page == 100
  end

  test "lists only real directories and supported videos in directory-first pages", %{root: root} do
    Enum.each(1..101, fn number ->
      File.mkdir_p!(
        Path.join(root, "Directory #{String.pad_leading(Integer.to_string(number), 3, "0")}")
      )
    end)

    File.write!(Path.join(root, "movie.MKV"), "video")
    File.write!(Path.join(root, "notes.txt"), "not a video")
    File.write!(Path.join(root, ".hidden.mp4"), "hidden")

    File.ln_s!("/dev/null", Path.join(root, "linked.mp4"))
    File.ln_s!(Path.join(root, "Directory 001"), Path.join(root, "linked-directory"))

    assert {:ok, first_page} = FileBrowser.list(root)
    assert first_page.total_entries == 102
    assert first_page.total_pages == 2
    assert length(first_page.entries) == 100
    assert Enum.all?(first_page.entries, &(&1.kind == :directory))
    assert Enum.all?(first_page.entries, &(&1.id != &1.path))

    refute Enum.any?(
             first_page.entries,
             &(&1.name in ["linked.mp4", "linked-directory", "notes.txt", ".hidden.mp4"])
           )

    assert {:ok, second_page} = FileBrowser.list(root, page: 2)
    assert Enum.map(second_page.entries, & &1.kind) == [:directory, :video]
    assert Enum.map(second_page.entries, & &1.name) == ["Directory 101", "movie.MKV"]
  end

  test "filters the current folder without changing hidden-file policy", %{root: root} do
    File.mkdir_p!(Path.join(root, "archive"))
    File.write!(Path.join(root, "alpha.mp4"), "a")
    File.write!(Path.join(root, "beta.webm"), "b")
    File.write!(Path.join(root, ".private.avi"), "c")

    assert {:ok, page} = FileBrowser.list(root, query: "ALPHA")
    assert page.query == "ALPHA"
    assert Enum.map(page.entries, & &1.name) == ["alpha.mp4"]
    refute page.show_hidden?

    assert {:ok, hidden_page} = FileBrowser.list(root, query: "private", show_hidden?: true)
    assert hidden_page.show_hidden?
    assert Enum.map(hidden_page.entries, & &1.name) == [".private.avi"]
  end

  test "returns safe directory errors and rejects out-of-range pages", %{root: root} do
    file = Path.join(root, "not-a-directory.mp4")
    File.write!(file, "video")

    assert {:error, :directory_not_found} = FileBrowser.list(Path.join(root, "gone"))
    assert {:error, :not_a_directory} = FileBrowser.list(file)
    assert {:error, :page_out_of_range} = FileBrowser.list(root, page: 2)
  end

  test "does not render unreadable folders", %{root: root} do
    unreadable = Path.join(root, "unreadable")
    File.mkdir_p!(unreadable)
    File.chmod!(unreadable, 0o000)

    on_exit(fn -> File.chmod(unreadable, 0o700) end)

    assert {:error, :directory_not_readable} = FileBrowser.list(unreadable)
  end
end
