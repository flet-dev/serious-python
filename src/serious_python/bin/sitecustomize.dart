String sitecustomizePy = """
# A site customization that can be used to trick pip into installing packages cross-platform.
# The folder containing this file should be on your PYTHONPATH pip is invoked.

custom_system = "{platform}"
custom_platform = "{tag}"
custom_mac_ver = "{mac_ver}"

import platform
import sysconfig

if custom_system:
    platform.system = lambda: custom_system

if custom_platform:
    sysconfig.get_platform = lambda: custom_platform

if custom_mac_ver:
  orig_mac_ver = platform.mac_ver

  def custom_mac_ver_impl():
      orig = orig_mac_ver()
      return orig[0], orig[1], custom_mac_ver

  platform.mac_ver = custom_mac_ver_impl


orig_platform_version = platform.version
platform.version = lambda: orig_platform_version() + ";embedded"
""";
