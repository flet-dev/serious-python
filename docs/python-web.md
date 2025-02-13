# Cross-Platform Python Companion for Flutter

This guide explains how to create and use a Python companion application that works across different platforms (Web, Desktop) using the serious_python package.

## Setup

### Project Structure
```
your_flutter_project/
├── python_companion/
│     ├── desktop/
│     │   ├── __init__.py
│     │   └── companion_server.py    # Flask server for desktop
│     ├── web/
│     │   ├── __init__.py
│     │   └── command_handler.py     # Command handling for web
│     ├── functionality/
│     │   ├── __init__.py
│     │   └── your_functions.py      # Shared functionality
│     ├── requirements/
│     │   ├── base.txt              # Shared dependencies
│     │   ├── desktop.txt           # Desktop-specific requirements
│     │   └── web.txt               # Web-specific (Pyodide) requirements
│     ├── python_companion_desktop.py  # Desktop entry point
│     └── python_companion_web.py      # Web entry point
```

### Requirements Files

```txt
# requirements/base.txt
numpy>=1.20.0
scipy>=1.7.0

# requirements/web.txt
-r base.txt
# Only Pyodide-compatible versions
h5py==3.8.0

# requirements/desktop.txt
-r base.txt
flask>=2.0.0
h5py==3.9.0
```

### Implementation

1. Desktop Implementation (Flask Server):
```python
# desktop/companion_server.py
from flask import Flask, request, jsonify
import functionality

app = Flask(__name__)

@app.route('/your_endpoint', methods=['POST'])
def your_endpoint():
    result = functionality.your_function(request.json)
    return jsonify(result)

def run_server():
    app.run(port=50001, debug=False, use_reloader=False)
```

2. Web Implementation (Pyodide):
```python
# web/command_handler.py
import json
import functionality

_command_functions = {
    "your_command": lambda data: functionality.your_function(data),
}

def handle_command(command: str, data):
    command_function = _command_functions.get(command)
    try:
        loaded_data = json.loads(data)
    except:
        loaded_data = data
    return command_function(data)
```

3. Shared Functionality:
```python
# functionality/your_functions.py

def your_function(json_data):
    # Your implementation
    return {"result": "success"}
```

4. Entry Points:
```python
# python_companion_desktop.py
from desktop import run_server

if __name__ == '__main__':
    run_server()

# python_companion_web.py
import os
from web import handle_command

if __name__ == '__main__':
    command = os.environ.get("PYODIDE_COMMAND", "")
    data = os.environ.get("PYODIDE_DATA", None)
    pyodide_result = handle_command(command, data)
```

### Packaging

Package your Python companion for different platforms:

```bash
# For Web (Pyodide)
dart run serious_python:main package \
  --asset assets/python_companion.zip python_companion/ \
  -p Pyodide \
  --requirements "-r,python_companion/requirements/web.txt"

# For Desktop (Linux)
dart run serious_python:main package \
  --asset assets/python_companion.zip python_companion/ \
  -p Linux \
  --requirements "-r,python_companion/requirements/desktop.txt"
```

## Usage in Flutter

1. Add serious_python to your pubspec.yaml:
```yaml
dependencies:
  serious_python: ^latest_version
```

2. Create a service class:
```dart
class PythonCompanionService {
  Future<Either<Exception, Map<String, dynamic>>> callPythonFunction(List<double> data);
}

class PythonCompanionServiceWeb implements PythonCompanionService {
  Future<Either<Exception, Map<String, dynamic>>> callPythonFunction(List<double> data) async {
    final String? result = await SeriousPython.run(
      'assets/python_companion.zip',
      appFileName: 'python_companion_web.py',
      modulePaths: ['python_companion/web', 'python_companion/functionality'],
      environmentVariables:
      {
        'PYODIDE_COMMAND': 'your_command',
        'PYODIDE_DATA': jsonEncode({'data': data})
      },
      sync: true,
    );

    if (result == null || result.isEmpty) {
      return left(Exception('Failed to execute Python function'));
    }

    return right(jsonDecode(result));
  }
}

class PythonCompanionServiceDesktop implements PythonCompanionService {
  @override
  Future<void> startServer() async {
    try {
      // Start the Python server
      await SeriousPython.run(
        'assets/python_companion.zip',
        appFileName: 'python_companion_desktop.py',
      );

      // Wait for server to be ready, e.g. by checking the health endpoint
      await _waitForServer();
      _isServerRunning = true;
    } catch (e) {
      throw Exception('Failed to start Python server: $e');
    }
  }

  @override
  Future<Either<Exception, Map<String, dynamic>>> callPythonFunction(List<double> data) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/your_endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': data}),
      );

      if (response.statusCode != 200) {
        return left(Exception('Server error: ${response.statusCode}'));
      }

      return right(jsonDecode(response.body));
    } catch (e) {
      return left(Exception('Error calling Python function: $e'));
    }
  }
}
```

3. Use in your Flutter app:
```dart
final pythonService = PythonCompanionService();

void yourFunction() async {
  final result = await pythonService.callPythonFunction([1.0, 2.0, 3.0]);
  result.fold(
    (error) => print('Error: $error'),
    (success) => print('Success: $success'),
  );
}
```

## Important Notes

1. **Web Compatibility**: Ensure all Python packages used in web implementation are [Pyodide-compatible](https://pyodide.org/en/stable/usage/packages-in-pyodide.html).

2. **Package Versions**: Use platform-specific package versions when needed (e.g., different h5py versions for web and desktop).

3. **Error Handling**: Implement proper error handling in both Python and Dart code.

4. **Data Transfer**: Use JSON for data transfer between Flutter and Python.

5. **Resource Management**: Properly manage resources (close files, connections, etc.).

## Troubleshooting

1. **Module Import Issues**: Ensure correct module paths and dependencies.
2. **Platform Compatibility**: Check package compatibility for each platform.
3. **Port Conflicts**: For desktop, ensure the Flask server port (50001) is available.
4. **Memory Management**: Be mindful of memory usage, especially with large data operations.

## Best Practices

1. Keep shared functionality platform-independent
2. Implement proper error handling and logging
3. Use type hints and documentation
4. Follow platform-specific conventions
5. Test on all target platforms
