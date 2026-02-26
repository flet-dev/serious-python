# -*- coding: utf-8 -*-
"""
Configuration module - responsible for loading configurations from environment variables

This module loads configuration from environment variables and provides
default values when environment variables are not set.
"""

import os
import sys
from typing import Optional, Dict, Any

import logging

# SearXNG Configuration
SEARXNG_HOST = os.getenv("SEARXNG_HOST", "127.0.0.1")
SEARXNG_PORT = int(os.getenv("SEARXNG_PORT", "8888"))

TAVILY_TIMEOUT = os.environ.get('TAVILY_TIMEOUT', "10")
TAVILY_CONTENT_LENGTH = os.environ.get('TAVILY_CONTENT_LENGTH', "2500")
TAVILY_MAX_RESULTS = os.environ.get('TAVILY_MAX_RESULTS', "10")
TAVILY_USER_AGENT = os.environ.get('TAVILY_USER_AGENT',"Mozilla/5.0 (compatible; TavilyBot/1.0)")


# Default log format
DEFAULT_LOG_FORMAT = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'

def setup_logger(level: str = "INFO", log_format: Optional[str] = None) -> logging.Logger:
    """
   Configure and return the application logger.

    Args:
        level: Log level, optional values:DEBUG, INFO, WARNING, ERROR, CRITICAL
        log_format: Log format; if None, the default format will be used.

    Returns:
        logging.Logger: Configured logger
    """
   # Set log level
    numeric_level = getattr(logging, level.upper(), logging.INFO)
    logger.setLevel(numeric_level)

    # If there is no processor, add a console processor.
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter(log_format or DEFAULT_LOG_FORMAT)
        handler.setFormatter(formatter)
        logger.addHandler(handler)

    return logger

# Function to export configuration information
def get_config_info() -> Dict[str,Any]:
    """
    Returns a dictionary of the current configuration information.

    Returns:
        dict: A dictionary containing all configuration parameters
    """
    return {
        "searxng": {
            "host": os.getenv("SEARXNG_HOST", SEARXNG_HOST),
            "port": os.getenv("SEARXNG_PORT", str(SEARXNG_PORT)),
        },
        "crawler": {
            "max_results": int(os.getenv("TAVILY_MAX_RESULTS", TAVILY_MAX_RESULTS)),
            "content_length": int(os.getenv("TAVILY_CONTENT_LENGTH", TAVILY_CONTENT_LENGTH)),
            "timeout": int(os.getenv("TAVILY_TIMEOUT", TAVILY_TIMEOUT)),
            "user_agent": str(os.getenv("TAVILY_USER_AGENT", TAVILY_USER_AGENT)),
        },
    }

logger = logging.getLogger(__name__)
