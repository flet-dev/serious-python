import asyncio
from enum import Enum
from typing import Optional, Any

from mcp_utils.core import ResponseQueueProtocol
from mcp_utils.schema import MCPResponse
from pydantic import BaseModel, Field
from queuelib.queue import FifoMemoryQueue


class SearxCategory(str, Enum):
    general = 'general'
    news = 'news'
    images = 'images'
    music = 'music'
    videos = 'videos'
    files =  'files'
    weather = 'weather'
    social_media = 'social media'
    map = 'map'
    books = 'books'
    web = 'web'
    it = 'it'
    repos = 'repos'
    software_wikis = 'software wikis'
    packages = 'packages'
    code = 'code'
    currency = 'currency'
    dictionaries = 'dictionaries'
    shopping = 'shopping'
    movies = 'movies'
    q_and_a = 'q&a'
    radio = 'radio'
    science = 'science'
    scientific_publications = 'scientific publications'

class SearxTimeRange(str, Enum):
    day = 'day'
    week = 'week'
    month = 'month'
    year = 'year'

class TavilyResult(BaseModel):
    url: str = Field(description="Url used for result", default=None)
    title: str = Field(description="Title of result", default=None)
    content: str = Field(description="Content for result", default=None)
    score: float = Field(description="Score rank for result", default=0.0)
    text: Optional[str] = Field(description="Extracted text for result", default=None)
    raw_content: Optional[str] = Field(description="Raw html for result", default=None)


class TavilyResponse(BaseModel):
    query: str = Field(description="Search query", default=None)
    follow_up_questions: Optional[list[str]] = Field(description="Follow-up questions", default=None)
    answer: Optional[str] = Field(description="Answer to query", default=None)
    images: Optional[list[str]] = Field(description="Image result provided to query", default=None)
    results: list[TavilyResult] = Field(description="List of results for query", default=[])
    response_time: float = Field(description="List of results for query", default=None)
    request_id: str = Field(description="Request id for query", default=None)

class InMemoryResponseQueue(ResponseQueueProtocol):
    def __init__(self):
        super().__init__(self)
        self._queues : dict[str, FifoMemoryQueue] = {}

    def push_response(
        self,
        session_id: str,
        response: MCPResponse,
    ) -> None:
        """
        Push a response to the queue for a specific session

        Args:
            session_id: The session ID
            response: The response to push
        """
        _queue = self._queues.get(session_id, FifoMemoryQueue())
        _queue.push(response)
        self._queues[session_id] = _queue

    async def wait_for_response(
        self, session_id: str, timeout: float | None = None
    ) -> MCPResponse | None:
        """
        Wait for a response from the queue for a specific session

        Args:
            session_id: The session ID
            timeout: How long to wait for a response in seconds.
                    If None, wait indefinitely.
                    If 0, return immediately if no response is available.

        Returns:
            The next queued response or None if timeout occurs
        """

        if timeout == 0:
            # Non-blocking check
            _queue = self._queues.get(session_id, FifoMemoryQueue())
            data = _queue.pop() if _queue.len() > 0 else None
            self._queues[session_id] = _queue
        else:
            # Blocking wait with timeout
            # coroutine to execute in a new task
            async def response():
                # generate a random value between 0 and 1
                waiting = True
                result = None
                _queue = self._queues.get(session_id, FifoMemoryQueue())
                while waiting:
                    result, waiting = (_queue.pop(), False)  if _queue.len() > 0 else (None, True)
                    # block for a moment
                    await asyncio.sleep(0.1)
                self._queues[session_id] = _queue
                return result
            try:
                data = await asyncio.wait_for(response(),timeout=timeout)
            except:
                data = None

        return data

    def clear_session(self, session_id: str) -> None:
        """
        Clear all queued responses for a session

        Args:
            session_id: The session ID to clear
        """
        self._queues.pop(session_id, FifoMemoryQueue())

class InMemoryFlipFlopQueue(ResponseQueueProtocol):
    def __init__(self):
        super().__init__(self)
        self._queues : dict[str, MCPResponse | None] = {}

    def push_response(
        self,
        session_id: str,
        response: MCPResponse,
    ) -> None:
        """
        Push a response to the queue for a specific session

        Args:
            session_id: The session ID
            response: The response to push
        """
        self._queues[session_id] = response

    async def wait_for_response(
        self, session_id: str, timeout: float | None = None
    ) -> MCPResponse | None:
        """
        Wait for a response from the queue for a specific session

        Args:
            session_id: The session ID
            timeout: How long to wait for a response in seconds.
                    If None, wait indefinitely.
                    If 0, return immediately if no response is available.

        Returns:
            The next queued response or None if timeout occurs
        """
        return self._queues.pop(session_id, None)

    def clear_session(self, session_id: str) -> None:
        """
        Clear all queued responses for a session

        Args:
            session_id: The session ID to clear
        """
        self._queues.pop(session_id, None)
