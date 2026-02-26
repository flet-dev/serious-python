import asyncio
import json
import typing as t
import httpx

from flask import Flask, Response
from flask.typing import RouteCallable
from mcp_utils.core import MCPServer
from mcp_utils.schema import TextContent, CallToolResult
from pydantic import Field
from searx.extended_types import sxng_request

from shared.types import SearxCategory, SearxTimeRange, InMemoryFlipFlopQueue
from tavily.adapter import adapter_after_request, adapter_before_request

# Create a basic MCP server
mcp: MCPServer = MCPServer(name='mcp-server', version='1.0', response_queue=InMemoryFlipFlopQueue())

class SearxngMcpAdapter:
    __instance  = None
    __endpoint: RouteCallable | None = None

    @staticmethod
    def get_mcp_adapter():
        if not SearxngMcpAdapter.__instance :
            SearxngMcpAdapter.__instance = SearxngMcpAdapter()
        return SearxngMcpAdapter.__instance


    @staticmethod
    def search() -> Response:
        if not SearxngMcpAdapter.__endpoint:
            from searx.webapp import search
            SearxngMcpAdapter.__endpoint = search
        return SearxngMcpAdapter.__endpoint()


@mcp.tool(name="web_search")
def web_search(
        query: str = Field(description="Search query", default=None),
        language: str = Field(
            description="Language code for search results (e.g., 'auto','en', 'de', 'fr'). Default: 'en'",
            default="auto",
        ),
        time_range: t.Literal['day', 'week', 'month', 'year','all'] | str | None = Field(
            description="Time range for search results. Options: 'day', 'week', 'month', 'year', 'all'. Default: all (no time restriction).",
            default='all'
        ),
        categories: t.List[t.Literal['general','news','images','music','videos','files','weather','social media','map','science','books','movies','web','scientific publications','dictionaries','software wikis','code' ]] | t.List[str] | None = Field(
            description = "Categories to search in (e.g., 'general', 'images', 'news').",
            default_factory=list
        ),
        engines: t.Optional[t.List[str]] = Field(
            description="Specific search engines to use (e.g., 'google', 'yahoo', 'wikipedia', 'brave').",
            default_factory=list
        ),
        safe_search: t.Literal[0, 1, 2] = Field(
            description="Safe-Search filter (0:normal, 1:moderate, 2:strict). Default: 1 (moderate).",
            default=1,
        ),
        page_no: int = Field(
            description="Page number for results. Must be minimum 1. Default: 1.",
            default=1,
            ge=1,
        ),
        max_results: t.Optional[int] = Field(
            description="Maximum number of search results to return. Range: 1-50. Default: 10.",
            default=5,
            ge=1,
            le=50,
        ),
        scrape_content: t.Optional[t.Literal[0, 1]] = Field(
            description="Whether or not to crawl and scrape contents of url results (0:no, 1:yes). Default: 0 (no).",
            default=0
        ),
        include_raw_content: t.Literal[0, 1] = Field(
            description="Include the cleaned and parsed HTML content of each search result. (0:no, 1:yes). Default: 0 (no).",
            default=0
        ),
        content_length: t.Optional[int] = Field(
            description="Maximum content length of search results. Range: 100-5000. Default: 2500.",
            default=2500,
            ge=100,
            le=5000,
        ),
    ) -> CallToolResult:
    """Perform web searches using SearXNG, a privacy-respecting metasearch engine, returning relevant web content with customizable parameters.
    Returns a Dictionary response with status, message, data (search results), and error if any."""
    params = {
                'q': query,
                'format': 'json',
                'language': language,
                'pageno': str(page_no),
                'engines': ",".join(engines) if engines and len(engines) > 0 else "wikipedia,duckduckgo,google,brave,yahoo",
                'safesearch': str(safe_search),
                'scrape_content':  str(scrape_content) if scrape_content else '0',
                'include_raw_content': str(include_raw_content) if include_raw_content else '0',
                'max_results': str(max_results) if max_results else '10',
                'content_length': str(content_length) if content_length else '2500'
            }
    if categories and len(categories) > 0:
        sxng_categories  = [ str(v) for v in categories if str(v) in SearxCategory.__members__ ]
        params['categories'] =  ",".join(sxng_categories) if len(sxng_categories) > 0 else "general,web"

    if time_range and (str(time_range) in SearxTimeRange.__members__ ):
        params['time_range'] = str(time_range) # time_range if time_range else 'None',

    sxng_request.form.update(params)
    adapter_before_request()

    response = SearxngMcpAdapter.search()
    try:
        loop = asyncio.get_running_loop()
    except Exception:
        asyncio.set_event_loop(asyncio.new_event_loop())
        loop = asyncio.get_event_loop()

    try:
        response = loop.run_until_complete(adapter_after_request(response=response))
    finally:
        loop.close()

    search_response: t.Dict[str, t.Any] = response.json

    contents = [TextContent(text=r["text"] if scrape_content == 1 and len(r.get("text","")) > 0 else r["content"], type="text") for r in search_response.get("results", []) if r and len(r) > 0]

    answer = contents[0] if len(contents) > 0 else TextContent(text="", type="text")

    result = CallToolResult(content=[answer], isError=False)
    return result

# @mcp.tool(name="get_weather")
# def get_weather_forecast(
#         latitude: float = Field(
#             description="Latitude of the location"
#         ),
#         longitude: float = Field(
#             description="Longitude of the location"
#         ),
#     ) -> CallToolResult:
#     """Get weather forecast for a location."""
