"""Module with circular/forward references between classes."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Node:
    """A node in a linked list."""

    value: int
    next: Node | None = None


@dataclass
class Tree:
    """A binary tree node."""

    value: int
    left: Tree | None = None
    right: Tree | None = None


@dataclass
class Parent:
    """Parent references Child."""

    name: str
    children: list[Child] | None = None


@dataclass
class Child:
    """Child references Parent."""

    name: str
    parent: Parent | None = None
