import argparse
import csv
import json
import sys
from dataclasses import asdict
from .client import Client, FreeProxyError, to_proxy_url

def main(argv=None):
    parser = argparse.ArgumentParser(prog="litport-free-proxies")
    parser.add_argument("--source", choices=("api", "github"), default="api")
    parser.add_argument("--protocol"); parser.add_argument("--country"); parser.add_argument("--anonymity")
    parser.add_argument("--https", choices=("true", "false")); parser.add_argument("--max-latency-ms", type=int); parser.add_argument("--min-uptime7d", type=int); parser.add_argument("--min-checks7d", type=int); parser.add_argument("--checked-within-min", type=int, default=30); parser.add_argument("--limit", type=int); parser.add_argument("--format", choices=("txt", "json", "csv"), default="txt")
    try:
        args = vars(parser.parse_args(argv)); args["https"] = None if args["https"] is None else args["https"] == "true"; source = args.pop("source"); fmt = args.pop("format")
        rows = Client(source=source).get_proxies(args)
        if not rows: return 2
        if fmt == "txt": sys.stdout.write("\n".join(to_proxy_url(row) for row in rows) + "\n")
        elif fmt == "json": sys.stdout.write(json.dumps([asdict(row) for row in rows], indent=2) + "\n")
        else:
            writer = csv.DictWriter(sys.stdout, fieldnames=asdict(rows[0]).keys()); writer.writeheader(); writer.writerows(asdict(row) for row in rows)
        return 0
    except (FreeProxyError, ValueError) as error:
        print(str(error), file=sys.stderr); return 1
if __name__ == "__main__": raise SystemExit(main())
