# Dependency Finder Script

This script is designed to analyze Tuist projects by parsing the `graph.json` file and displaying dependencies of a given target in a clear and interactive format. It supports color-coded outputs, visualization, and advanced filtering options.

---

## Features

- Displays dependencies of a given target in a hierarchical (nested) or flat structure.
- Supports visualization with `.png` and `.svg` outputs.
- Filters dependencies by ignoring specific suffixes.
- Provides size information (color-coded) for dependencies based on disk usage:
  - **Yellow-Green**: Size < 3MB.
  - **Yellow**: 3MB ≤ Size < 7MB.
  - **Orange**: 7MB ≤ Size < 15MB.
  - **Orange-Red**: 15MB ≤ Size < 30MB.
  - **Red**: Size ≥ 30MB.

---

## Requirements

- **Tuist**: Ensure Tuist is installed and configured.
- **Graphviz**: Required for visualization (`dot` command).
- **jq**: JSON processor used for parsing `graph.json`.

---

## Usage

### Running the Script
Make the script executable and run it:
```
chmod +x dependencyFinder.sh
./dependencyFinder.sh [options] <target_name>
```

### Options
- `-n, --nested`: Show dependencies in a tree-like format.
- `-v, --visualize`: Generate a dependency graph as PNG and SVG files.
- `--diff`: Display dependencies unrelated to the given target.
- `--ignore-suffix <suffixes>`: Ignore dependencies ending with specified suffixes.
- `-h, --help`: Show help message.

---

## Examples

1. **Basic Usage**:
   ```
   ./dependencyFinder.sh MyLibrary
   ```

2. **Nested Dependencies**:
   ```
   ./dependencyFinder.sh --nested MyLibrary
   ```

3. **Visualization**:
   ```
   ./dependencyFinder.sh --visualize MyLibrary
   ```

4. **Find Unrelated Dependencies**:
   ```
   ./dependencyFinder.sh --diff MyLibrary
   ```

5. **Ignore Suffixes in Diff**:
   ```
   ./dependencyFinder.sh --ignore-suffix Tests Mock --diff MyLibrary
   ```

---

## Output Description

### Nested Dependency Output Example

If you run:
```
./dependencyFinder.sh --nested ExampleModule
```

The output will look like this:

```
--------------------------------------------
Dependencies of ExampleModule:
--------------------------------------------
- ExampleModule (15M)
  - MyModule (7.2M)
    - MyModuleInterface (1.5M)
    - MyModuleTests (5.5M)
  - SharedUtils (20M)
    - SharedUtilsInterface (1M)
    - SharedUtilsTests (2M)
  - NetworkManager.xcframework (25M)
--------------------------------------------
Depends to ExampleModule:
--------------------------------------------
- SharedUtils
- MyModule
--------------------------------------------
NOT RELATED WITH ExampleModule:
--------------------------------------------
- UtilityLibrary
- AnotherModuleTests
- SampleMock
- RandomHelper
```

---

### Visualization Output
When the `-v` flag is used, the script generates:
- `dependency_graph.png`
- `dependency_graph.svg`

These files contain a graphical representation of the dependency tree.

---

## Notes

1. If `graph.json` does not exist, the script will automatically generate it using:
   ```
   tuist graph -f json > graph.json
   ```

2. Ensure `dot` (Graphviz) is installed for visualization:
   ```
   sudo apt install graphviz
   ```

3. The script works best in a terminal that supports ANSI colors.

---

## License

This script is open-source and provided under the MIT License. Feel free to use and modify it.
