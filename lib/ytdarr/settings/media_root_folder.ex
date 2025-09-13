defmodule Ytdarr.Settings.MediaRootFolder do
  use Ecto.Schema
  import Ecto.Changeset

  schema "media_root_folders" do
    field :path, :string
    field :purpose, :string, default: "videos"
    field :active, :boolean, default: true
    timestamps()
  end

  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:path, :purpose, :active])
    |> validate_required([:path, :purpose])
    |> unique_constraint(:path)
  end
end
