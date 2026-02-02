"""Module testing various name conversion edge cases."""
    """Acronym at start."""
    """Another acronym."""
    """Acronym in middle."""
    """Multiple acronyms."""
    """Single letter."""
    """Two letters."""
    """Acronym then word."""
    """Function with acronym."""
    """Already snake_case.

---
atomyst <https://github.com/m-gris/atomyst>
Source: input.py | 2026-02-02T12:42:04Z

Large files are hostile to AI agents—they read everything to edit anything.
One definition per file. Atomic edits. No collisions.
`tree src/` reveals the architecture at a glance.
"""

from .class_simple_class import SimpleClass
from .class_http_server import HTTPServer
from .class_xml_parser import XMLParser
from .class_my_http_client import MyHTTPClient
from .class_aws_lambda_handler import AWSLambdaHandler
from .class_a import A
from .class_ab import AB
from .class_abc_def import ABCDef
from .def_get_http_response import getHTTPResponse
from .def_simple_function import simple_function

__all__ = [
    "SimpleClass",
    "HTTPServer",
    "XMLParser",
    "MyHTTPClient",
    "AWSLambdaHandler",
    "A",
    "AB",
    "ABCDef",
    "getHTTPResponse",
    "simple_function",
]
