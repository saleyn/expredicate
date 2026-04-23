defmodule BenchmarkFormatter do
  @moduledoc """
  Helper module for formatting benchmark results as ASCII tables.
  Displays all times in microseconds with improvement ratios.
  """

  @doc       """
  Format benchmark results as a table.

  Accepts benchmarks as tuples with numeric microsecond values:
    {name, non_indexed_us, indexed_us, adaptive_us}

  - non_indexed_us is the baseline
  - indexed_us and adaptive_us show ratios like "15us (0.80x)"
  - Use nil for unavailable values like N/A

  Example:
    results = [
      {"Insert 100", 10.5, 8.4, 9.3},
      {"Match 1000", 2300.0, 920.0, 500.0}
    ]
    BenchmarkFormatter.table(results)
  """
  def table(results, _title \\ "BENCHMARKS") when is_list(results) do
    # Format all values: convert to "time (ratio)" format
    formatted_results = Enum.map(results, &format_benchmark/1)

    col_widths        = calculate_widths(formatted_results)    # Find column widths

    lines             = [                                      # Build output
      horizontal_line(col_widths),
      header_row(col_widths),
      horizontal_line(col_widths)
    ]

    lines =
      lines ++
        Enum.map(formatted_results, fn row -> format_row(row, col_widths) end)

    lines = lines ++ [horizontal_line(col_widths)]

    Enum.join(lines, "\n")
  end

  @doc """
  Format simple benchmark results with just name and time.

  Accepts benchmarks as tuples with numeric microsecond values:
    {name, time_us}

  Example:
    results = [
      {"Insert 100 rules", 10500.0},
      {"Match 1000 rules", 2300.0}
    ]
    BenchmarkFormatter.simple_table(results)
  """
  def simple_table(results, _title \\ "BENCHMARKS") when is_list(results) do
    formatted_results =  # Format time values
      Enum.map(results, fn {name, time_us} -> {name, format_us(time_us)} end)

    headers = ["Benchmark", "Time"] # Calculate column widths

    col_widths =
      Enum.reduce(formatted_results, [0, 0], fn {name, time_str}, [w1, w2] ->
        [max(w1, String.length(name)), max(w2, String.length(time_str))]
      end)

    col_widths =
      Enum.zip(headers, col_widths)
      |> Enum.map(fn {h, w} -> max(String.length(h), w) end)

    lines = [  # Build output
      horizontal_line(col_widths),
      simple_header_row(col_widths),
      horizontal_line(col_widths)
    ]

    lines =
      lines ++
        Enum.map(formatted_results, fn {name, time_str} ->
          simple_format_row({name, time_str}, col_widths)
        end)

    lines = lines ++ [horizontal_line(col_widths)]

    Enum.join(lines, "\n")
  end

  defp simple_header_row(col_widths) do
    headers = ["Benchmark", "Time"]

    formatted =
      Enum.zip(headers, col_widths)
      |> Enum.map(fn {h, w} -> pad_cell(h, w) end)
      |> Enum.join("|")

    "| " <> formatted <> " |"
  end

  defp simple_format_row({name, time_str}, col_widths) do
    values = [name, time_str]

    formatted =
      Enum.zip(values, col_widths)
      |> Enum.map(fn {val, w} -> pad_cell(val, w) end)
      |> Enum.join("|")

    "| " <> formatted <> " |"
  end

  # Convert a benchmark tuple from numeric values to formatted strings
  # {name, non_indexed_us, indexed_us, adaptive_us} -> {name, "baseline", "indexed (ratio)", "adaptive (ratio)"}
  defp format_benchmark({name, non_indexed_us, indexed_us, adaptive_us}) do
    non_indexed_str = format_us(non_indexed_us)

    indexed_str =
      if indexed_us && is_number(indexed_us) && is_number(non_indexed_us) && non_indexed_us > 0 do
        ratio = Float.round(non_indexed_us / indexed_us, 2)
        "#{format_us(indexed_us)} (#{ratio}x)"
      else
        "N/A"
      end

    adaptive_str =
      if adaptive_us && is_number(adaptive_us) && is_number(non_indexed_us) && non_indexed_us > 0 do
        ratio = Float.round(non_indexed_us / adaptive_us, 2)
        "#{format_us(adaptive_us)} (#{ratio}x)"
      else
        "N/A"
      end

    {name, non_indexed_str, indexed_str, adaptive_str}
  end

  # Format microseconds with appropriate precision and unit
  defp format_us(us) when is_number(us) do
    us_float = us / 1.0 # Convert to float to handle both integer and float inputs

    cond do
      us_float >= 1_000_000 -> "#{Float.round(us_float / 1_000_000, 3)}ms"
      us_float >= 1_000     -> "#{Float.round(us_float / 1_000, 3)}ms"
      true                  -> "#{Float.round(us_float, 2)}μs"
    end
  end

  defp format_us(nil), do: "N/A"

  defp calculate_widths(results) do
    headers = ["Benchmark", "Non-indexed", "Indexed", "Adaptive"]

    col_widths =
      Enum.reduce(results, [0, 0, 0, 0], fn row, widths -> row_tuple = Tuple.to_list(row)

        Enum.zip(widths, row_tuple)
        |> Enum.map(fn {w, val} -> max(w, String.length(to_string(val))) end)
      end)

    headers
    |> Enum.zip(col_widths)
    |> Enum.map(fn {h, w} -> max(String.length(h), w) end)
  end

  defp horizontal_line(col_widths) do
    # The row format is: "| " + cells separated by "|" + " |"
    last_col_idx = Enum.count(col_widths) - 1 # So we need dashes that account for these spaces

    dashes =
      col_widths
      |> Enum.with_index()
      |> Enum.map(fn {w, i} ->
        String.duplicate("-", ((i == 0 or i == last_col_idx) && w + 1) || w)
      end)

    "+" <> Enum.join(dashes, "+") <> "+"
  end

  defp header_row(col_widths) do
    headers = ["Benchmark", "Non-indexed", "Indexed", "Adaptive"]

    formatted =
      Enum.zip(headers, col_widths)
      |> Enum.map(fn {h, w} -> pad_cell(h, w) end)
      |> Enum.join("|")

    "| " <> formatted <> " |"
  end

  defp format_row(row, col_widths) do
    row_list = Tuple.to_list(row)

    formatted =
      Enum.zip(row_list, col_widths)
      |> Enum.map(fn {val, w} -> pad_cell(to_string(val), w) end)
      |> Enum.join("|")

    "| " <> formatted <> " |"
  end

  defp pad_cell(text, width) do
    padding   = width - String.length(text)
    left_pad  = div(padding + 1, 2)
    right_pad = padding - left_pad
    String.duplicate(" ", left_pad) <> text <> String.duplicate(" ", right_pad)
  end
end