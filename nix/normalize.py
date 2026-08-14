import json
import os
import sys

KEEP = {
    "content-type",
    "etag",
    "last-modified",
    "access-control-allow-origin",
    "x-content-type-options",
    "x-frame-options",
}

marker = b"// denoCacheMetadata="

for root, _dirs, files in os.walk(os.path.join(sys.argv[1], "remote")):
    for name in files:
        p = os.path.join(root, name)
        with open(p, "rb") as f:
            data = f.read()
        i = data.rfind(marker)
        if i < 0:
            continue
        # File layout is `<body>\n// denoCacheMetadata=<json>` with no trailing
        # newline. Drop only the single separator byte so the stored body stays
        # byte-for-byte identical (Deno verifies it against the lockfile hash).
        content = data[: i - 1]
        meta = json.loads(data[i + len(marker):].rstrip(b"\n"))
        headers = {
            k: v for k, v in meta.get("headers", {}).items() if k.lower() in KEEP
        }
        # The CDN includes `content-length` only intermittently (chunked /
        # conditional responses omit it), which would make the metadata vary
        # between builds. Derive it from the stored body instead.
        headers["content-length"] = str(len(content))
        norm = json.dumps(
            {"headers": dict(sorted(headers.items())), "url": meta["url"], "time": 4102444800},
            separators=(",", ":"),
        )
        with open(p, "wb") as f:
            f.write(content + b"\n" + marker + norm.encode())