"""
Tavily-compatible client for SearXNG
Provides same interface as tavily-python package but uses SearXNG backend
"""
import asyncio
import os
import time
import uuid
from pathlib import Path

import aiohttp
import yaml

from bs4 import BeautifulSoup
from flask import Blueprint, Response
from flask.typing import RouteCallable
from platformdirs import user_config_dir
from pydantic import BaseModel
from searx.extended_types import SXNG_Request
from searx.extended_types import sxng_request

from shared.types import TavilyResult, TavilyResponse

TAVILY_APP_NAME = os.environ.get('TAVILY_APP_NAME', "tavily_adapter")
TAVILY_APP_AUTHOR = os.environ.get('TAVILY_APP_AUTHOR', "Konnek Inc")

TAVILY_CONFIG_FILE= f"{TAVILY_APP_NAME.lower()}_config.yml"
TAVILY_CONFIG_DIR = user_config_dir(TAVILY_APP_NAME, TAVILY_APP_AUTHOR)

class TavilyAdapterConfig(BaseModel):
    """
    Configuration loader for Tavily adapter
    """
    timeout: int | None = 10
    user_agent: str | None = "Mozilla/5.0 (compatible; SearchBot/1.0)"
    settings: str | None = Path(TAVILY_CONFIG_DIR) / TAVILY_CONFIG_FILE

def get_tavily_config(cfg: TavilyAdapterConfig = TavilyAdapterConfig()) -> TavilyAdapterConfig:
    """
    Load configuration from unified YAML file
    """
    default_settings = Path(__file__).parent / "settings" / "tavily_defaults.yml"
    defaults = yaml.safe_load(default_settings.read_text())
    if cfg.settings:
        config_path = Path(cfg.settings)
        if config_path.exists():
            settings = yaml.safe_load(config_path.read_text())
            app_settings = settings["crawler"] if settings.get("crawler") else defaults["crawler"]
            return TavilyAdapterConfig(
                timeout= int(cfg.timeout if cfg.timeout else app_settings["timeout"]),
                user_agent=cfg.user_agent if cfg.user_agent else app_settings["user_agent"],
                settings = str(config_path)
            )

    return TavilyAdapterConfig(
                timeout=  int(os.getenv("TAVILY_TIMEOUT", cfg.timeout)),
                user_agent= str(os.getenv("TAVILY_USER_AGENT", cfg.user_agent)),
                settings = ""
            )



class TavilyAdapter:
    __instance  = None
    __adapter_config: TavilyAdapterConfig | None = TavilyAdapterConfig()
    def __init__(self, api_key: str = "", route: RouteCallable | None = None):
        self.api_key = api_key  # Not used, but kept for compatibility
        self._search = route

    @property
    def search(self):
        return self._search

    @search.setter
    def search(self, value):
        self._search = value

    @search.deleter
    def search(self):
        del self._search

    @staticmethod
    async def _fetch_raw_content(session: aiohttp.ClientSession, url: str, include_raw_content: bool, content_length: int) -> dict[str, str] | None:
        """
        Scraps a page and returns the first 2500 characters of text
        """
        try:
            async with session.get(
                    url,
                    timeout=aiohttp.ClientTimeout(total=TavilyAdapter.__adapter_config.timeout),
                    headers={'User-Agent': TavilyAdapter.__adapter_config.user_agent}
            ) as response:
                if response.status != 200:
                    return None

                html = await response.text()
                soup = BeautifulSoup(html, 'html.parser')

                # Remove unnecessary things
                for tag in soup(['script', 'style', 'nav', 'header', 'footer', 'aside']):
                    tag.decompose()

                # Take the text
                text = soup.get_text(strip=True, separator=" ")

                # Crop to the specified size
                if len(text) > content_length:
                    text = text[:content_length] + "..."
                result = {'url': url, 'text': text, 'raw': html if include_raw_content else ''}
                return result
        except Exception:
            return None

    @staticmethod
    def update_request(request: SXNG_Request):
        """
        Update the
        Args:
            request: SXNG_Request that is to be updated

        Returns:
            An updated SXNG_Request
        """
        request.form.update({
            'pageno': request.form.get('pageno','1'),
            'format': 'json',
        })

    @staticmethod
    async def crawl(
            response: Response
    ) -> TavilyResponse:
        """
        Search using SearXNG with Tavily-compatible interface

        Args:
            response: SearXNG Response from metasearch
        Returns:
            A TavilyResponse as dictionary
        """
        start_time = time.time()
        request_id = str(uuid.uuid4())
        include_raw_content: bool = int(sxng_request.form.get('include_raw_content','0')) == 0
        scrape_content: bool = int(sxng_request.form.get('scrape_content', '0')) == 1
        content_length: int = int(sxng_request.form.get('content_length', '2500'))
        max_results: int = int(sxng_request.form.get('max_results', '10'))
        searxng_results = [ r for r in response.json.get("results", []) if r and isinstance(r, dict) and r.get("url")]
        accepted_results = searxng_results[:max_results]
        raw_contents: dict[str, tuple] | None= None
        if scrape_content and accepted_results:
            urls_to_scrape = [r["url"] for r in accepted_results if r.get("url")]
            async with aiohttp.ClientSession() as scrape_session:
                tasks = [TavilyAdapter._fetch_raw_content(scrape_session, url, include_raw_content, content_length) for url in urls_to_scrape]
                page_contents = await asyncio.gather(*tasks, return_exceptions=True)
                raw_contents = { content['url'] : (content['text'], content['raw']) for content in page_contents if content and isinstance(content, dict)}

        # tokenized_corpus: dict[str, list[str]] = {r["url"]: r.get("content", '').split(" ") for r in accepted_results}
        # tokenized_query = sxng_request.form.get('q').split(" ")
        # bm25 = BM25Plus(tokenized_corpus.values())
        # doc_scores = bm25.get_scores(tokenized_query)
        # try:
        #     float_list = [float(x) for x in doc_scores.tolist()]
        #     scores: dict[str, float] | None = dict(zip(tokenized_corpus.keys(), float_list))
        # except (ValueError, TypeError):
        #     scores = None

        results = [TavilyResult(
                    url=result["url"],
                    title=result.get("title", ""),
                    content=result.get("content", ""),
                    score=  float(result["score"]) if result.get("score") else 0.9 - (i * 0.05),
                    text=raw_contents.get(result["url"])[0] if raw_contents and raw_contents.get(result["url"]) and  len(raw_contents.get(result["url"]))>0 else "",
                    raw_content= raw_contents.get(result["url"])[1]  if raw_contents and raw_contents.get(result["url"]) and  len(raw_contents.get(result["url"]))>1 else "",
                ) for i, result in enumerate(accepted_results) if result and result.get("url")]

        response_time = time.time() - start_time

        return TavilyResponse(
            query=sxng_request.form.get('q'),
            follow_up_questions=None,
            answer=None,
            images=[],
            results=results,
            response_time=response_time,
            request_id=request_id,
        )

    @staticmethod
    def configure_tavily_adapter(tavily_config: TavilyAdapterConfig):
        TavilyAdapter.__adapter_config = tavily_config
        TavilyAdapter.__instance = TavilyAdapter()

    @staticmethod
    def get_tavily_adapter():
        if not TavilyAdapter.__instance :
            TavilyAdapter.__instance = TavilyAdapter()
        return TavilyAdapter.__instance

    @staticmethod
    def get_tavily_config():
        return TavilyAdapter.__adapter_config

adapter = Blueprint(name='tavily', import_name=__name__, url_prefix="/adapter")

@adapter.before_request
def adapter_before_request():
    TavilyAdapter.update_request(sxng_request)


@adapter.after_request
async def adapter_after_request(response: Response):
    results: TavilyResponse = await TavilyAdapter.crawl(response)
    results_json: str = results.model_dump_json()
    response.data = results_json
    return response