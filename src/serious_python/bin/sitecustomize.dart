String sitecustomizePy = """
# A site customization that can be used to trick pip into installing packages cross-platform.
# The folder containing this file should be on your PYTHONPATH pip is invoked.

custom_system = "{platform}"
custom_platform = "{tag}"
custom_mac_ver = "{mac_ver}"

import collections
import platform
import sysconfig
import sys

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

if custom_system == "iOS":
  IOSVersionInfo = collections.namedtuple(
      "IOSVersionInfo",
      ["system", "release", "model", "is_simulator"]
  )

  tag_parts = custom_platform.split("-")

  def custom_ios_ver(system="", release="", model="", is_simulator=False):
      return IOSVersionInfo(custom_system, tag_parts[1], "iPhone", "simulator" in tag_parts[3])

  platform.ios_ver = custom_ios_ver

  sys.implementation._multiarch = f"{tag_parts[2]}_{tag_parts[3]}"

orig_platform_version = platform.version
platform.version = lambda: orig_platform_version() + ";embedded"
""";
