#!/bin/bash

# ANSI color codes
GREEN="\033[32m"
DARK_GREEN="\033[1;32m"
BLUE="\033[34m"
PURPLE="\033[35m"
RED="\033[31m"
RESET="\033[0m"

# Path to the JSON file
JSON_FILE="$(pwd)/graph.json"

# Default values
NESTED=false
VISUALIZE=false
DIFF=false

IGNORE_SUFFIXES=()

# Show help function
show_help() {
  echo -e "${PURPLE}Usage:${RESET}"
  echo "  ./dependencyFinder.sh [options] <target_name>"
  echo ""
  echo -e "${PURPLE}Options:${RESET}"
  echo -e "  -n, --nested\t\tShow nested dependencies in a tree-like format"
  echo -e "  -v, --visualize\tGenerate a dependency graph as PNG and SVG files"
  echo -e "  --diff\t\t\Show dependencies that are not related to the given target"
  echo -e "  --ignore-suffix\t\t\It can take array. Used when showing diffs. It ignores and does not show targets ending with certain letters."
  echo -e "  -h, --help\t\tShow this help message"
  echo ""
  echo -e "${PURPLE}Examples:${RESET}"
  echo "  ./dependencyFinder.sh --n -v MyLibrary"
  echo "  ./dependencyFinder.sh -diff MyLibrary"
  echo "  ./dependencyFinder.sh --ignore-suffix Tests TestSupport --diff MyLibrary"
  echo "  ./dependencyFinder.sh -v MyLibrary"
  echo ""
  echo -e "${PURPLE}Description:${RESET}"
  echo "  This script analyzes Tuist projects and displays their dependencies."
  echo "  If 'graph.json' does not exist, it will be generated using 'tuist graph -f json'."
  echo ""
  echo -e "${GREEN}Visualization:${RESET}"
  echo "  When the '-v' flag is used, the script creates two files:"
  echo "    - dependency_graph.png"
  echo "    - dependency_graph.svg"
  echo "  The files represent the dependency tree in a graphical format."
  echo ""
  echo -e "${RED}Note:${RESET}"
  echo "  Ensure that Tuist is installed and configured properly for this script to work."
}

get_paths() {
  local target_name="$1"
  jq -r --arg TARGET_NAME "$target_name" '
    .projects[] | select(.name == $TARGET_NAME) | .targets[].dependencies[]? |
    if has("project") then
      .project.path // empty
    elif has("xcframework") then
      .xcframework.path // empty
    else
      empty
    end
  ' "$JSON_FILE"
}

get_path_for_target() {
  local target="$1"
  jq -r --arg TARGET "$target" '
    .projects[]?
    | if .name == $TARGET then
        .path // empty
      else
        [
          .targets[]?.dependencies[]?
          | select(.xcframework?.path? // empty | endswith($TARGET))
          | .xcframework.path // empty
        ] | unique | .[0] // empty
      end
  ' "$JSON_FILE" | head -n 1
}

calculate_size() {
  local path="$1"
  if [[ -d "$path" ]]; then
    du -sh "$path" 2>/dev/null | awk '
    BEGIN {
      YELLOW_GREEN="\033[38;5;148m"
      YELLOW="\033[38;5;226m"
      ORANGE="\033[38;5;214m"
      ORANGE_RED="\033[38;5;202m"
      RED="\033[38;5;196m"
      RESET="\033[0m"
    }
    {
      size=$1
      unit=substr(size, length(size))
      value=substr(size, 1, length(size)-1) + 0  # Sayısal dönüşüm

      if (unit == "K" || unit == "k") { value = value / 1024 }
      else if (unit == "M" || unit == "m") { value = value }
      else if (unit == "G" || unit == "g") { value = value * 1024 }
      else if (unit == "T" || unit == "t") { value = value * 1024 * 1024 }

      if (value >= 30) {
        color = RED
      } else if (value >= 15) {
        color = ORANGE_RED
      } else if (value >= 7) {
        color = ORANGE
      } else if (value >= 3) {
        color = YELLOW
      } else {
        color = YELLOW_GREEN
      }

      printf "%s(%sB)%s\n", color, size, RESET
    }'
  fi
}


# Iterative function to process dependencies using a stack
process_dependents() {
  local INITIAL_TARGET_NAME=$1
  STACK+=("$INITIAL_TARGET_NAME")
  DEPTH_STACK+=(0)
  echo -e "${PURPLE}--------------------------------------------${RESET}"
  echo -e "${PURPLE}Depends to $INITIAL_TARGET_NAME:${RESET}"
  echo -e "${PURPLE}--------------------------------------------${RESET}"

  while [ ${#STACK[@]} -gt 0 ]; do
    local CURRENT=${STACK[-1]}
    local CURRENT_DEPTH=${DEPTH_STACK[-1]}
    STACK=("${STACK[@]::${#STACK[@]}-1}")
    DEPTH_STACK=("${DEPTH_STACK[@]::${#DEPTH_STACK[@]}-1}")

    if [[ -n "${LISTED_PROJECTS[$CURRENT]}" ]]; then
      echo -e "$(printf ' %.0s' $(seq 1 "$CURRENT_DEPTH"))${GREEN}- $CURRENT (already listed)${RESET}"
      continue
    fi

    LISTED_PROJECTS["$CURRENT"]=1
    if [ "$CURRENT" != "$INITIAL_TARGET_NAME" ]; then
        echo -e "$(printf ' %.0s' $(seq 1 "$CURRENT_DEPTH"))${DARK_GREEN}- $CURRENT${RESET}"
    fi

    if [ "$VISUALIZE" == true ]; then
      if [ "$CURRENT" != "$INITIAL_TARGET_NAME" ]; then
        echo "  \"$INITIAL_TARGET_NAME\" -> \"$CURRENT\";" >> "$DOT_FILE"
      fi
    fi


    local DEPENDENTS=($(jq -r --arg TARGET_NAME "$CURRENT" '
    .projects[] | .targets[] | select(.dependencies[]? | (has("project") and .project.target == $TARGET_NAME) or (has("xcframework") and .xcframework.target == $TARGET_NAME)) | .name
    ' "$JSON_FILE"))
    if [ "$NESTED" == false ] && [ "$CURRENT_DEPTH" -gt 0 ]; then
      continue
    fi
    for dep in "${DEPENDENTS[@]}"; do
      if [[ -n "$dep" ]]; then
        STACK+=("$dep")
        DEPTH_STACK+=($((CURRENT_DEPTH + 2)))
        if [ "$VISUALIZE" == true ]; then
          echo "  \"$CURRENT\" -> \"$dep\";" >> "$DOT_FILE"
        fi
      fi
    done
  done
  if [[ ${#LISTED_PROJECTS[@]} -eq 1 ]]; then
    echo -e "${GREEN}Not found any depend target.${RESET}"
  fi
}

# Recursive function to print dependencies and visualize them
print_nested_dependencies() {
  local CURRENT_TARGET=$1
  local INDENT_LEVEL=$2

  # Avoid nested same dependencies
  if [[ -n "${LISTED_DEPENDENCIES[$CURRENT_TARGET]}" ]]; then
    #echo -e "$(printf ' %.0s' $(seq 1 $INDENT_LEVEL))${GREEN}- $CURRENT_TARGET (already listed)${RESET}"
    return
  fi
  # Mark the current target as listed
  LISTED_DEPENDENCIES["$CURRENT_TARGET"]=1
  CURRENT_TARGET=$(echo "$CURRENT_TARGET" | xargs)

  if [[ "$CURRENT_TARGET" != "$TARGET_NAME" ]]; then
      # Print the current target
      path=$(get_path_for_target "$CURRENT_TARGET")
      size=$(calculate_size "${path}")
      case "$CURRENT_TARGET" in
        *.xcframework)
        echo -e "$(printf ' %.0s' $(seq 1 $INDENT_LEVEL))${BLUE}- $CURRENT_TARGET ${size}${RESET}"
        ;;
        *)
        echo -e "$(printf ' %.0s' $(seq 1 $INDENT_LEVEL))${DARK_GREEN}- $CURRENT_TARGET ${size}${RESET}"
        ;;
      esac
  fi
  if [ "$VISUALIZE" == true ]; then
    echo "  \"$CURRENT_TARGET\";" >> "$DOT_FILE"
  fi

  # Get dependencies of the current target
  local DEPENDENCIES=($(jq -r --arg TARGET_NAME "$CURRENT_TARGET" '
    .projects[] | select(.name == $TARGET_NAME) | .targets[].dependencies[]? |
    if has("project") then
      if .project | has("target") then
        .project.target
      else
        (.project.path | split("/") | last)
      end
    elif has("xcframework") then
      if .xcframework | has("path") then
        (.xcframework.path | split("/") | last)
      else
        .xcframework.target
      end
    else
      empty
    end
  ' "$JSON_FILE"))

  GLOBAL_DEPENDENCIES+=("${DEPENDENCIES[@]}")
  # Recursively print each dependency
  for dep in "${DEPENDENCIES[@]}"; do
    if [ "$VISUALIZE" == true ]; then
      echo "  \"$CURRENT_TARGET\" -> \"$dep\";" >> "$DOT_FILE"
    fi
    print_nested_dependencies "$dep" $((INDENT_LEVEL + 2))
  done
}

# Check for input parameters
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--nested)
      NESTED=true
      shift
      ;;
    --diff)
      DIFF=true
      NESTED=true
      shift
      ;;
    -v|--visualize)
      VISUALIZE=true
      shift
      ;;
    --ignore-suffix)
      shift
      while [[ $# -gt 0 && "$1" != -* ]]; do
        IGNORE_SUFFIXES+=("$1")
        shift
      done
      ;;
    -h|--help|help)
      show_help
      exit 0
      ;;
    *)
      TARGET_NAME=$1
      shift
      ;;
  esac
done

if [ -z "$TARGET_NAME" ]; then
  echo -e "${RED}Error:${RESET} Please provide a project name or use the '-h' flag for help."
  exit 1
fi

# If graph.json does not exist, generate it using `tuist graph -f json`
if [ ! -f "$JSON_FILE" ]; then
  echo -e "${RED}JSON file not found: $JSON_FILE${RESET}"
  echo -e "${BLUE}Running 'tuist graph -f json' to generate the graph.json...${RESET}"
  tuist graph -f json > "$JSON_FILE"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to generate graph.json using Tuist. Please check your Tuist setup.${RESET}"
    exit 1
  fi
  echo -e "${GREEN}graph.json successfully generated!${RESET}"
fi

# Arrays to track already listed projects
declare -A LISTED_PROJECTS
declare -a STACK
declare -a DEPTH_STACK
declare -A LISTED_DEPENDENCIES
GLOBAL_DEPENDENCIES=()

# Create a temporary DOT file if visualization is enabled
if [ "$VISUALIZE" == true ]; then
  DOT_FILE="$(pwd)/dependency_graph.dot"
  echo "digraph G {" > "$DOT_FILE"
  echo "  node [shape=box];" >> "$DOT_FILE"
fi

# Start printing dependencies from the target
echo -e "${PURPLE}--------------------------------------------${RESET}"
echo -e "${PURPLE}Dependencies of $TARGET_NAME:${RESET}"
echo -e "${PURPLE}--------------------------------------------${RESET}"

if [ "$NESTED" == true ]; then
  print_nested_dependencies "$TARGET_NAME" 0
else
  DEPENDENCIES=($(jq -r --arg TARGET_NAME "$TARGET_NAME" '
    .projects[] | select(.name == $TARGET_NAME) | .targets[].dependencies[]? |
    if has("project") then
      if .project | has("target") then
        .project.target
      else
        (.project.path | split("/") | last)
      end
    elif has("xcframework") then
      if .xcframework | has("path") then
        (.xcframework.path | split("/") | last)
      else
        .xcframework.target
      end
    elif has("target") then
      if .target | has("name") then
        .target.name
      end
    else
      empty
    end
  ' "$JSON_FILE"))
  for dep in "${DEPENDENCIES[@]}"; do
    if [[ -z "${LISTED_DEPENDENCIES[$dep]}" ]]; then
      LISTED_DEPENDENCIES["$dep"]=1
      if [[ "$dep" == *.xcframework ]]; then
        echo -e "${BLUE}- $dep${RESET}"
      else
        echo -e "${DARK_GREEN}- $dep${RESET}"
      fi
      if [ "$VISUALIZE" == true ]; then
        echo "  \"$TARGET_NAME\" -> \"$dep\";" >> "$DOT_FILE"
      fi
    fi
  done
fi

# Process dependencies iteratively if nested
process_dependents "$TARGET_NAME"

if [ "$DIFF" == true ]; then
    ALL_TARGETS=($(jq -r '
      .projects | to_entries[] | .value.targets[]? | .name
    ' "$JSON_FILE"))

    echo -e "${PURPLE}--------------------------------------------${RESET}"
    echo -e "${PURPLE}NOT RELATED WITH ${TARGET_NAME}${RESET}"
    echo -e "${PURPLE}--------------------------------------------${RESET}"
    for item in "${ALL_TARGETS[@]}"; do
      # Flag to determine if the current item should be excluded
      exclude=false

      # Check against GLOBAL_DEPENDENCIES
      for dep in "${GLOBAL_DEPENDENCIES[@]}"; do
          if [[ ${#IGNORE_SUFFIXES[@]} -eq 0 ]]; then
          # If IGNORE_SUFFIXES is empty, only check exact match
              if [[ "$item" == "$dep" || "$item" == "$TARGET_NAME" ]]; then
                  exclude=true
                  break
              fi
              else
              # If IGNORE_SUFFIXES is not empty, check combinations with suffixes
              for suffix in "${IGNORE_SUFFIXES[@]}"; do
                  if [[ "$item" == *"$suffix" || "$item" == "$dep" ]]; then
                  exclude=true
                  break 2
                  fi
              done
          fi
      done

      # Print the item if it is not excluded
      if [[ "$exclude" == false ]]; then
          echo -e "${DARK_GREEN}- $item${RESET}"
      fi
    done
fi

# Generate visualization if enabled
if [ "$VISUALIZE" == true ]; then
  echo -e "${PURPLE}Visualization in progress... It take may few minutes.${RESET}"
  echo "}" >> "$DOT_FILE"
  dot -Tpng "$DOT_FILE" -o dependency_graph.png
  dot -Tsvg "$DOT_FILE" -o dependency_graph.svg
  echo -e "${PURPLE}Visualization saved as dependency_graph.png and dependency_graph.svg.${RESET}"
fi
