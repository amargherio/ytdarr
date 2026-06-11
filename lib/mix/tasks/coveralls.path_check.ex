defmodule Mix.Tasks.Coveralls.PathCheck do
  @moduledoc """
  Enforce per-path minimum coverage thresholds defined in `coveralls.json`.

  Reads `cover/excoveralls.json` (produced by `mix coveralls.json`) and the
  `path_thresholds` list from `coveralls.json` at the project root. Each entry
  has a `pattern` (regex matched against the source file path) and a `minimum`
  percentage. Files matching multiple patterns use the highest threshold.

  Files skipped via `skip_files` are not present in the report and are ignored.
  A file with zero relevant lines is treated as covered.

  Exits with status 1 if any tracked file falls below its tier.

      mix coveralls.json
      mix coveralls.path_check
  """
  use Mix.Task

  @shortdoc "Check per-path coverage thresholds"

  @report_path "cover/excoveralls.json"
  @config_path "coveralls.json"

  @impl Mix.Task
  def run(_args) do
    config = load_config()
    thresholds = Map.get(config, "path_thresholds", [])

    if thresholds == [] do
      Mix.shell().info("coveralls.path_check: no path_thresholds configured, skipping")
      :ok
    else
      report = load_report()
      compiled = compile_thresholds(thresholds)
      violations = collect_violations(report["source_files"] || [], compiled)
      report_results(violations)
    end
  end

  defp load_config do
    case File.read(@config_path) do
      {:ok, body} ->
        Jason.decode!(body)

      {:error, reason} ->
        Mix.raise("coveralls.path_check: cannot read #{@config_path}: #{inspect(reason)}")
    end
  end

  defp load_report do
    case File.read(@report_path) do
      {:ok, body} ->
        Jason.decode!(body)

      {:error, reason} ->
        Mix.raise(
          "coveralls.path_check: cannot read #{@report_path} (run `mix coveralls.json` first): #{inspect(reason)}"
        )
    end
  end

  defp compile_thresholds(thresholds) do
    Enum.map(thresholds, fn %{"pattern" => pattern, "minimum" => minimum} ->
      {Regex.compile!(pattern), minimum * 1.0}
    end)
  end

  defp collect_violations(source_files, compiled) do
    source_files
    |> Enum.flat_map(fn %{"name" => name, "coverage" => coverage} ->
      case applicable_minimum(name, compiled) do
        nil ->
          []

        minimum ->
          percent = percent_covered(coverage)

          if percent < minimum do
            [{name, percent, minimum}]
          else
            []
          end
      end
    end)
    |> Enum.sort_by(fn {name, _, _} -> name end)
  end

  defp applicable_minimum(name, compiled) do
    compiled
    |> Enum.filter(fn {regex, _} -> Regex.match?(regex, name) end)
    |> Enum.map(fn {_, minimum} -> minimum end)
    |> case do
      [] -> nil
      minima -> Enum.max(minima)
    end
  end

  defp percent_covered(coverage) when is_list(coverage) do
    relevant = Enum.reject(coverage, &is_nil/1)

    case relevant do
      [] ->
        100.0

      lines ->
        covered = Enum.count(lines, &(&1 > 0))
        covered / length(lines) * 100
    end
  end

  defp report_results([]) do
    Mix.shell().info("coveralls.path_check: all tracked paths meet their thresholds")
    :ok
  end

  defp report_results(violations) do
    Mix.shell().error("coveralls.path_check: #{length(violations)} file(s) below threshold:")

    Enum.each(violations, fn {name, percent, minimum} ->
      Mix.shell().error(
        "  #{name}: #{:erlang.float_to_binary(percent, decimals: 2)}% (min #{:erlang.float_to_binary(minimum, decimals: 2)}%)"
      )
    end)

    exit({:shutdown, 1})
  end
end
