defmodule Ytdarr.Settings.AppSetting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_settings" do
    field :key, :string
    field :value, :map
    field :type, :string
    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :type])
    |> validate_required([:key, :value, :type])
    |> unique_constraint(:key)
  end
end
