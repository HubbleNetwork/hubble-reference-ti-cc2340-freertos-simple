#!/bin/bash
# Memory analysis script for TI CC2340R5 firmware
# Parses linker map file and displays memory usage statistics

set -e

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Device specifications
FLASH_TOTAL=512000  # 500 KB (0x7D000)
RAM_TOTAL=36864     # 36 KB (0x9000)

# Thresholds
WARN_THRESHOLD=75
CRITICAL_THRESHOLD=90

MAP_FILE=$1
MODE=${2:-summary}

# Check if map file exists
if [ ! -f "$MAP_FILE" ]; then
    echo "Error: Map file not found: $MAP_FILE"
    echo "Run 'make' first to generate build artifacts."
    exit 1
fi

# Convert hex to decimal
hex_to_dec() {
    echo $((16#$1))
}

# Format bytes with units
format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        printf "%d bytes" $bytes
    elif [ $bytes -lt 1048576 ]; then
        printf "%.2f KB" $(echo "scale=2; $bytes/1024" | bc)
    else
        printf "%.2f MB" $(echo "scale=2; $bytes/1048576" | bc)
    fi
}

# Generate progress bar
progress_bar() {
    local percent=$1
    local width=20
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    # Determine color
    local color=$GREEN
    if [ $percent -ge $CRITICAL_THRESHOLD ]; then
        color=$RED
    elif [ $percent -ge $WARN_THRESHOLD ]; then
        color=$YELLOW
    fi

    printf "${color}["
    for ((i=0; i<filled; i++)); do printf "█"; done
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] %d%%${NC}" $percent
}

# Parse memory configuration section
parse_memory_config() {
    awk '
    /^MEMORY CONFIGURATION/,/^$/ {
        if (NR > 3 && NF >= 5 && $1 ~ /^[A-Z]/) {
            name = $1
            origin = $2
            length = $3
            used = $4
            unused = $5

            # Remove 0x prefix and convert hex to decimal
            gsub(/^0x/, "", used)
            gsub(/^0x/, "", unused)

            printf "%s %s %s\n", name, used, unused
        }
    }' "$MAP_FILE"
}

# Parse segment allocation map
parse_segments() {
    awk '
    /^SEGMENT ALLOCATION MAP/,/^SECTION ALLOCATION MAP/ {
        # Look for lines ending with section names (starting with .)
        if ($0 ~ /\.[a-z][a-zA-Z0-9_:]*$/ && $3 != "00000000") {
            # $3 is the length field, $NF is the section name
            printf "%s %s\n", $NF, $3
        }
    }' "$MAP_FILE"
}

# Extract top functions from .text section
extract_top_functions() {
    local count=${1:-10}
    awk '
    /^\.text/ {
        in_text = 1
        next
    }
    in_text && /^[[:space:]]+[0-9a-f]+[[:space:]]+[0-9a-f]+[[:space:]]/ {
        # Parse: address size library : object (.text.functionName)
        # Example:   00000090    00000c78     rcl_cc23x0r5.a : ble5.c.obj (.text.RCL_Handler_BLE5_adv)
        size_hex = $2
        rest = $0

        # Extract function name from parentheses if present
        if (match(rest, /\(\.text[:.][^)]+\)/)) {
            func_part = substr(rest, RSTART+1, RLENGTH-2)
            # Remove .text. or .text: prefix
            gsub(/^\.text[.:]/, "", func_part)
            symbol = func_part
        } else if (match(rest, /\([^)]+\)/)) {
            symbol = substr(rest, RSTART+1, RLENGTH-2)
        } else {
            symbol = $NF
        }

        # Convert hex to decimal
        cmd = sprintf("echo $((16#%s))", size_hex)
        cmd | getline dec_size
        close(cmd)

        if (dec_size > 0 && symbol != "" && symbol !~ /^\.[a-z]+$/) {
            print dec_size, symbol
        }
    }
    /^[^[:space:]]/ && in_text {
        in_text = 0
    }
    ' "$MAP_FILE" | sort -rn | head -n "$count"
}

# Calculate memory usage
calculate_usage() {
    # Parse memory configuration
    local flash_used=0
    local ram_used=0

    # Parse segments to categorize usage
    local text_size=0
    local rodata_size=0
    local cinit_size=0
    local data_size=0
    local bss_size=0
    local stack_size=0

    while read -r section size_hex; do
        local size_dec=$(hex_to_dec "$size_hex")

        case "$section" in
            .text)
                text_size=$size_dec
                flash_used=$((flash_used + size_dec))
                ;;
            .rodata|.const)
                rodata_size=$((rodata_size + size_dec))
                flash_used=$((flash_used + size_dec))
                ;;
            .cinit)
                cinit_size=$size_dec
                flash_used=$((flash_used + size_dec))
                ;;
            .data)
                data_size=$size_dec
                ram_used=$((ram_used + size_dec))
                flash_used=$((flash_used + size_dec))  # .data is stored in flash too
                ;;
            .bss)
                bss_size=$size_dec
                ram_used=$((ram_used + size_dec))
                ;;
            .stack)
                stack_size=$size_dec
                ram_used=$((ram_used + size_dec))
                ;;
        esac
    done < <(parse_segments)

    # Calculate percentages
    local flash_percent=$((flash_used * 100 / FLASH_TOTAL))
    local ram_percent=$((ram_used * 100 / RAM_TOTAL))

    local flash_free=$((FLASH_TOTAL - flash_used))
    local ram_free=$((RAM_TOTAL - ram_used))

    # Store in global variables for different output modes
    FLASH_USED=$flash_used
    FLASH_FREE=$flash_free
    FLASH_PERCENT=$flash_percent
    RAM_USED=$ram_used
    RAM_FREE=$ram_free
    RAM_PERCENT=$ram_percent

    TEXT_SIZE=$text_size
    RODATA_SIZE=$rodata_size
    CINIT_SIZE=$cinit_size
    DATA_SIZE=$data_size
    BSS_SIZE=$bss_size
    STACK_SIZE=$stack_size
}

# Output summary mode
output_summary() {
    echo "================================================================"
    echo "  TI CC2340R5 Firmware Memory Usage Report"
    echo "================================================================"
    echo "  Build: $(basename "$MAP_FILE" .map).out"
    echo "  Date: $(date)"
    echo ""

    echo "FLASH Memory:"
    echo "  Total:     $FLASH_TOTAL bytes ($(format_bytes $FLASH_TOTAL))"
    printf "  Used:      %d bytes ($(format_bytes $FLASH_USED))  " $FLASH_USED
    progress_bar $FLASH_PERCENT
    echo ""
    echo "  Free:      $FLASH_FREE bytes ($(format_bytes $FLASH_FREE))"
    echo ""

    if [ $TEXT_SIZE -gt 0 ]; then
        echo "  Breakdown:"
        printf "    .text     (code)      : %d bytes  (%5.1f%% of used)\n" \
            $TEXT_SIZE $(echo "scale=1; $TEXT_SIZE*100/$FLASH_USED" | bc)
        printf "    .rodata   (constants) : %d bytes  (%5.1f%% of used)\n" \
            $RODATA_SIZE $(echo "scale=1; $RODATA_SIZE*100/$FLASH_USED" | bc)
        printf "    .cinit    (init data) : %d bytes  (%5.1f%% of used)\n" \
            $CINIT_SIZE $(echo "scale=1; $CINIT_SIZE*100/$FLASH_USED" | bc)
        echo ""
    fi

    echo "SRAM Memory:"
    echo "  Total:      $RAM_TOTAL bytes ($(format_bytes $RAM_TOTAL))"
    printf "  Used:       %d bytes ($(format_bytes $RAM_USED))   " $RAM_USED
    progress_bar $RAM_PERCENT
    echo ""
    echo "  Free:       $RAM_FREE bytes ($(format_bytes $RAM_FREE))"
    echo ""

    if [ $BSS_SIZE -gt 0 ]; then
        echo "  Breakdown:"
        printf "    .bss      (uninitialized): %d bytes  (%5.1f%% of used)\n" \
            $BSS_SIZE $(echo "scale=1; $BSS_SIZE*100/$RAM_USED" | bc)
        printf "    .data     (initialized)  : %d bytes  (%5.1f%% of used)\n" \
            $DATA_SIZE $(echo "scale=1; $DATA_SIZE*100/$RAM_USED" | bc)
        printf "    .stack                   : %d bytes  (%5.1f%% of used)\n" \
            $STACK_SIZE $(echo "scale=1; $STACK_SIZE*100/$RAM_USED" | bc)
        echo ""
    fi

    # Warnings
    if [ $RAM_PERCENT -ge $CRITICAL_THRESHOLD ]; then
        echo -e "${RED}⚠ WARNING: RAM usage is critically high (>$CRITICAL_THRESHOLD%)${NC}"
        echo "  Consider optimizing memory usage or reducing buffer sizes."
        echo ""
    elif [ $RAM_PERCENT -ge $WARN_THRESHOLD ]; then
        echo -e "${YELLOW}⚠ WARNING: RAM usage is high (>$WARN_THRESHOLD%)${NC}"
        echo "  Monitor memory usage carefully."
        echo ""
    fi

    if [ $FLASH_PERCENT -ge $CRITICAL_THRESHOLD ]; then
        echo -e "${RED}⚠ WARNING: Flash usage is critically high (>$CRITICAL_THRESHOLD%)${NC}"
        echo "  Consider removing unused features or optimizing code size."
        echo ""
    fi

    echo "================================================================"
}

# Output detailed mode
output_detailed() {
    output_summary

    echo ""
    echo "Top 10 Functions by Size:"
    echo "================================================================"
    printf "%-10s  %s\n" "Size" "Function"
    echo "----------------------------------------------------------------"

    while read -r size symbol; do
        printf "%-10s  %s\n" "$(format_bytes $size)" "$symbol"
    done < <(extract_top_functions 10)

    echo "================================================================"
}

# Output JSON mode
output_json() {
    cat <<EOF
{
  "device": "TI CC2340R5",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build": "$(basename "$MAP_FILE" .map).out",
  "flash": {
    "total": $FLASH_TOTAL,
    "used": $FLASH_USED,
    "free": $FLASH_FREE,
    "percent": $FLASH_PERCENT,
    "sections": {
      "text": $TEXT_SIZE,
      "rodata": $RODATA_SIZE,
      "cinit": $CINIT_SIZE
    }
  },
  "ram": {
    "total": $RAM_TOTAL,
    "used": $RAM_USED,
    "free": $RAM_FREE,
    "percent": $RAM_PERCENT,
    "sections": {
      "bss": $BSS_SIZE,
      "data": $DATA_SIZE,
      "stack": $STACK_SIZE
    }
  },
  "warnings": {
    "flash_critical": $([ $FLASH_PERCENT -ge $CRITICAL_THRESHOLD ] && echo "true" || echo "false"),
    "flash_warning": $([ $FLASH_PERCENT -ge $WARN_THRESHOLD ] && echo "true" || echo "false"),
    "ram_critical": $([ $RAM_PERCENT -ge $CRITICAL_THRESHOLD ] && echo "true" || echo "false"),
    "ram_warning": $([ $RAM_PERCENT -ge $WARN_THRESHOLD ] && echo "true" || echo "false")
  }
}
EOF
}

# Main execution
calculate_usage

case "$MODE" in
    summary)
        output_summary
        ;;
    detailed)
        output_detailed
        ;;
    json)
        output_json
        ;;
    *)
        echo "Error: Unknown mode '$MODE'"
        echo "Usage: $0 <map_file> [summary|detailed|json]"
        exit 1
        ;;
esac
