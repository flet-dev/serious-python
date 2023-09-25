# serious_python_platform_interface

A common platform interface for the `serious_python` plugin.

This interface allows platform-specific implementations of the `serious_python` plugin, as well as the plugin itself, to ensure they are supporting the same interface.

# Usage

To implement a new platform-specific implementation of `serious_python`, extend `SeriousPythonPlatform` with an implementation that performs the platform-specific behavior.