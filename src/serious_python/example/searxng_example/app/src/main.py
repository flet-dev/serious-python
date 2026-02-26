from common.config import setup_logger
from tavily.adapter import TavilyAdapterConfig, TavilyAdapter
from runner.simplexng import SearXNGServerConfig, SimpleXNGServer

# Default settings for the logger
sxng_config=SearXNGServerConfig()
setup_logger(level='ERROR')

server = SimpleXNGServer(server_config=sxng_config)
TavilyAdapter.configure_tavily_adapter(tavily_config=TavilyAdapterConfig(settings=None))
server.start_server()
