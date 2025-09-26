# NSKeyedArchiveViewer

Displays archives created with `NSKeyedArchiver` in a readable JSON format.

The storage format used by `NSKeyedArchiver` is optimized for size and speed, not readability. It places all objects in a single unsorted array and represents relationships through references into that array. This deduplicates identical objects and allows constant-time lookups. Although tools like `defaults` or `plutil` can dump such archives on macOS, their output is hard to interpret. This viewer presents the archive in a more readable form and exposes its object graph, which is essential for unarchiving when the original class implementations are unavailable.

To build the viewer, just execute

```
swiftc -o NSKeyedArchiveViewer src/NSKeyedArchiveViewer.swift
```
and run it with

```
./NSKeyedArchiveViewer <archive-path>
```