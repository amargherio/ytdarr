defmodule Ytdarr.Settings.QualityProfile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "quality_profiles" do
    field :name, :string
    field :max_height, :integer
    field :max_bitrate_kbps, :integer
    field :preferred_codecs, {:array, :string}, default: []
    field :allow_hdr, :boolean, default: true
    field :format_selector, :string
    field :is_default, :boolean, default: false
    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:name, :max_height, :max_bitrate_kbps, :preferred_codecs, :allow_hdr, :format_selector, :is_default])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
