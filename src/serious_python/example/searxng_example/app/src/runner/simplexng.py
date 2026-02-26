"""
SimpleXNG: A simple way to run SearXNG locally
"""
import logging
import os
import secrets
import signal
import sys
import webbrowser
from pathlib import Path
from threading import Timer
from typing import Any

import searx
import waitress
import yaml
from flask import Response, redirect, url_for
from platformdirs import user_config_dir
from pydantic import BaseModel
from searx.extended_types import sxng_request
from strif import AtomicVar

from common.config import logger
from mcp.server import SearxngMcpAdapter
from tavily.adapter import TavilyAdapter, TavilyAdapterConfig

SIMPLEXNG_APP_NAME = os.environ.get('SIMPLEXNG_APP_NAME', "AI4All")
SIMPLEXNG_APP_AUTHOR = os.environ.get('SIMPLEXNG_APP_AUTHOR', "Konnek Inc")

SEARXNG_SETTINGS_FILE = f"{SIMPLEXNG_APP_NAME.lower()}_settings.yml"
SEARXNG_SETTINGS_DIR = user_config_dir(SIMPLEXNG_APP_NAME, SIMPLEXNG_APP_AUTHOR)

# Web crawler configuration
CONTENT_FILTER_THRESHOLD = float(os.getenv("CONTENT_FILTER_THRESHOLD", "0.6"))
WORD_COUNT_THRESHOLD = int(os.getenv("WORD_COUNT_THRESHOLD", "10"))

_settings_path: AtomicVar[Path | None] = AtomicVar(None)

# SearXNG Server Config
class SearXNGServerConfig(BaseModel):
    """
    SearXNG Server Configuration
    Attributes:
        log_level: logging level of server (default: logging.INFO)
        host: Host to bind to (default: localhost).
        port: Port to run on (default: 8888)
        settings: Path to custom settings.yml file
        verbose: Enable verbose logging
    """
    log_level: int = logging.INFO
    host: str = "127.0.0.1"
    port: int = 11888
    app_name: str = SIMPLEXNG_APP_NAME
    settings: str = Path(SEARXNG_SETTINGS_DIR) / SEARXNG_SETTINGS_FILE
    verbose: bool = False


class SimpleXNGServer:
    def __init__(self, server_config: SearXNGServerConfig):
        self.searxng_server_config = server_config
        self.log = logging.getLogger(self.searxng_server_config.app_name)
        self.log.setLevel(level=self.searxng_server_config.log_level)

    @staticmethod
    def get_bundled_template() -> Path:
        return Path(__file__).parent / "settings" / "settings_template.yml"

    @staticmethod
    def get_settings_path() -> Path | None:
        return _settings_path.copy()

    def configure_server(self):
        """
        One-time initialization of settings.
        """
        settings_path = Path(self.searxng_server_config.settings)
        with _settings_path.lock:
            if _settings_path.value:
                raise RuntimeError("Settings already initialized")
            if settings_path.exists():
                logger.warning("Using specified settings file: %s", settings_path)
            else:
                # Create from template and host/port
                if not settings_path.parent.exists():
                    settings_path.parent.mkdir(parents=True, exist_ok=True)

            # This allows dynamic configuration of host/port/secret
            template_path = SimpleXNGServer.get_bundled_template()
            settings = yaml.safe_load(template_path.read_text())

            settings["general"]["debug"] = bool(searx.sxng_debug)
            settings["server"]["port"] = self.searxng_server_config.port
            settings["server"]["bind_address"] = self.searxng_server_config.host
            # Generate a cryptographically secure random secret key
            settings["server"]["secret_key"] = secrets.token_hex(16)

            content = (
                f"# Generated from template {template_path.name}\n"
                f"# Port: {self.searxng_server_config.port}, Host: {self.searxng_server_config.host}\n"
                f"# Random secret key generated automatically\n\n"
                f"{yaml.dump(settings, default_flow_style=False)}"
            )
            settings_path.write_text(content)

            logger.warning("Wrote new settings file (including random secret key): %s", settings_path)

            _settings_path.set(settings_path)

        # Set configs for SearXNG to use this path (and its parent as the config path)
        os.environ["SEARXNG_SETTINGS_PATH"] = str(settings_path)
        os.environ["SEARXNG_HOST"] = self.searxng_server_config.host
        os.environ["SEARXNG_PORT"] = str(self.searxng_server_config.port)
        searx.init_settings()


    def start_server(self):
        """
        Start the appropriate server.
        """

        self.configure_server()

        url = f"http://{self.searxng_server_config.host}:{self.searxng_server_config.port}"
        server_name = "Flask" if searx.sxng_debug else "Waitress"

        self.log.info(f"Starting {self.searxng_server_config.app_name} with {server_name} server...")
        self.log.info(f"URL: {url}")

        self.log.info(f'SEARXNG_SETTINGS_PATH={os.environ["SEARXNG_SETTINGS_PATH"]}')
        self.log.info(f'SEARXNG_HOST={os.environ["SEARXNG_HOST"]}')
        self.log.info(f'SEARXNG_PORT={os.environ["SEARXNG_PORT"]}')
        self.log.info(f"searxng_config={self.searxng_server_config}")

        from searx.webapp import app, search  # pyright: ignore
        from tavily.adapter import adapter

        @adapter.route('/query', methods=["POST"])
        def query():
            return search()

        app.register_blueprint(adapter)

        from mcp.server import mcp

        @app.route("/mcp", methods=["POST"])
        def mcp_route():
            message = mcp.handle_message(sxng_request.json)
            result: str = message.model_dump_json()
            return Response(response=result, mimetype='application/json')

        if searx.sxng_debug:
            Timer(2, lambda: webbrowser.open(url)).start()
            self.log.info("Opening browser...")
            app.run(host=self.searxng_server_config.host, port=self.searxng_server_config.port, debug=True)  # pyright: ignore[reportUnknownMemberType]
        else:
            waitress.serve(
                app,  # pyright: ignore[reportUnknownArgumentType]
                host=self.searxng_server_config.host,
                port=self.searxng_server_config.port,
                threads=4,
                connection_limit=100,
                cleanup_interval=30,
            )

        # Reset _settings_path
        with _settings_path.lock:
            _settings_path.set(None)


def main() -> None:
    """
    Main CLI entry point.
    """

    def signal_handler(_signum: int, _frame: Any) -> None:
        """
        Handle Ctrl+C gracefully.
        """
        log.warning("Shutting down SearXNG...")
        sys.exit(0)

    log = logging.getLogger(__name__)
    # Set up signal handling
    signal.signal(signal.SIGINT, signal_handler)

    try:
        server = SimpleXNGServer(server_config=SearXNGServerConfig())
        TavilyAdapter.configure_tavily_adapter(tavily_config=TavilyAdapterConfig(settings=None))
        server.start_server()
    except Exception as e:
        log.error(f"Error: {e.__class__.__name__}: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
