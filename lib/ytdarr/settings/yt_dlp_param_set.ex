defmodule Ytdarr.Settings.YtDlpParamSet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "yt_dlp_param_sets" do
    field :name, :string
    field :format, :string
    field :extra_args, :string
    field :rate_limit_kbps, :integer
    field :concurrency, :integer
    field :is_default, :boolean, default: false
    timestamps()
  end

  def changeset(param_set, attrs) do
    param_set
    |> cast(attrs, [:name, :format, :extra_args, :rate_limit_kbps, :concurrency, :is_default])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
