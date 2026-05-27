defmodule Ytdarr.Content.Channel.Validations.ValidUrl do
  @moduledoc "Validates that the URL is a valid http or https URL"
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, opts, _context) do
    url = Ash.Changeset.get_attribute(changeset, opts[:attribute])

    if is_nil(url) do
      :ok
    else
      case URI.parse(url) do
        %URI{scheme: nil} ->
          {:error, field: opts[:attribute], message: "must have a scheme (http or https)"}

        %URI{host: host} when host in [nil, ""] ->
          {:error, field: opts[:attribute], message: "must have a host"}

        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
          :ok

        _ ->
          {:error, field: opts[:attribute], message: "must be a valid http or https URL"}
      end
    end
  end
end
