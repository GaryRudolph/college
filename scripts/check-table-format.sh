#!/usr/bin/env bash
# Validates the main comparison table in decision.md.
#
# Rule (from .cursor/rules/decision-doc-formatting.mdc):
#   Every cell in the Engineering Reputation, Rowing Culture Fit, Cost,
#   and Risk columns MUST start with "**<Rating>.**<br>..." OR be a
#   rating-only cell "**<Rating>.**".
#
# This script locates the comparison table, parses rating-column cells,
# and fails if any cell has a bolded lead immediately followed by a space
# (indicating the <br> was stripped).

set -uo pipefail

FILE="${1:-decision.md}"

if [[ ! -f "$FILE" ]]; then
  echo "check-table-format: file not found: $FILE" >&2
  exit 2
fi

# Find the start of the main comparison table: the header line containing
# the five column names in order.
start_line=$(grep -n '^| Option .*| Engineering Reputation .*| Rowing Culture Fit .*| Tuition Cost.*| Risk .*|' "$FILE" | head -n1 | cut -d: -f1)

if [[ -z "$start_line" ]]; then
  # Accept shorter "Cost" column header as well.
  start_line=$(grep -n '^| Option .*| Engineering Reputation .*| Rowing Culture Fit .*| Cost .*| Risk .*|' "$FILE" | head -n1 | cut -d: -f1)
fi

if [[ -z "$start_line" ]]; then
  echo "check-table-format: could not locate main comparison table header in $FILE" >&2
  exit 2
fi

# Data rows start 2 lines below the header (skip the separator row).
data_start=$((start_line + 2))

# Data rows end at the first blank line (or non-table line) after data_start.
end_line=$(awk -v s="$data_start" 'NR>=s && !/^\|/ { print NR-1; exit }' "$FILE")
if [[ -z "$end_line" ]]; then
  end_line=$(wc -l < "$FILE")
fi

errors=0

# Iterate each row. Expected layout: | Option | Eng | Row | Cost | Risk |
# That's 5 pipe-separated cells + leading/trailing pipes.
while IFS= read -r line; do
  # Skip if not a data row
  [[ "$line" =~ ^\| ]] || continue

  # Use awk to split on '|' and strip leading/trailing whitespace per cell.
  # Fields 2..6 are: Option, Eng, Row, Cost, Risk.
  option=$(echo "$line" | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')
  for idx in 3 4 5 6; do
    cell=$(echo "$line" | awk -F'|' -v i="$idx" '{ gsub(/^[ \t]+|[ \t]+$/, "", $i); print $i }')
    col_name=""
    case $idx in
      3) col_name="Engineering Reputation" ;;
      4) col_name="Rowing Culture Fit" ;;
      5) col_name="Tuition Cost" ;;
      6) col_name="Risk" ;;
    esac

    # Empty cell: skip (shouldn't happen but don't false-positive)
    [[ -z "$cell" ]] && continue

    # Rating-only cell (e.g., "**Low.**") is allowed.
    if [[ "$cell" =~ ^\*\*[^*]+\*\*$ ]]; then
      continue
    fi

    # Otherwise cell must start with **...**<br>...
    # Valid: "**Strong.**<br>#64 ranked..."
    # Invalid: "**Strong.** #64 ranked..."  (space instead of <br>)
    if [[ "$cell" =~ ^\*\*[^*]+\*\*\<br\> ]]; then
      continue
    fi

    echo "FAIL: row [$option] column [$col_name]: missing <br> after bolded lead"
    echo "      cell content: $cell"
    errors=$((errors + 1))
  done
done < <(sed -n "${data_start},${end_line}p" "$FILE")

if (( errors > 0 )); then
  echo ""
  echo "check-table-format: $errors cell(s) in $FILE violate the <br>-after-bolded-lead rule."
  echo "See .cursor/rules/decision-doc-formatting.mdc section 1."
  exit 1
fi

echo "check-table-format: $FILE OK"
exit 0
