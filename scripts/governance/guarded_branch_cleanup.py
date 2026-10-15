"""Prune only GitHub branches strictly contained in main. Fail closed."""
import argparse
import json
import os
from urllib.parse import quote
from urllib.request import Request, urlopen


def eligible(branch, comparison, open_heads):
    name = branch.get("name", "")
    return (
        bool(name) and name != "main"
        and branch.get("protected") is False
        and name not in open_heads
        and comparison.get("ahead_by") == 0
        and comparison.get("behind_by", 0) > 0
        and comparison.get("status") == "behind"
    )


def collection(api, path):
    """Read a complete snapshot before any deletion changes pagination."""
    result = []
    for page in range(1, 21):
        rows = api(f"{path}&per_page=100&page={page}")
        result.extend(rows)
        if len(rows) < 100:
            return result
    raise RuntimeError("pagination_limit_reached_cleanup_blocked")


def active_pr_branches(api, repo):
    refs = set()
    for pr in collection(api, "/pulls?state=open"):
        for side in ("head", "base"):
            branch = pr.get(side) or {}
            if (branch.get("repo") or {}).get("full_name") == repo:
                refs.add(branch["ref"])
    return refs


def cleanup(api, repo, *, execute=False, max_deletes=10):
    if not 1 <= max_deletes <= 10:
        raise ValueError("max_deletes_must_be_between_1_and_10")
    open_refs = active_pr_branches(api, repo)
    branches = collection(api, "/branches?")
    report = {"dry_run": not execute, "candidates": [], "deleted": [],
              "max_deletes": max_deletes}
    for branch in branches:
        name = branch["name"]
        if name == "main":
            continue
        encoded = quote(name, safe="")
        comparison = api("/compare/main..." + encoded)
        if not eligible(branch, comparison, open_refs):
            continue
        report["candidates"].append(name)
        if not execute or len(report["deleted"]) >= max_deletes:
            continue
        fresh = api("/branches/" + encoded)
        fresh_compare = api("/compare/main..." + encoded)
        # PRs may be opened while the run is in progress. Protect both ends.
        fresh_refs = active_pr_branches(api, repo)
        if (fresh["commit"]["sha"] != branch["commit"]["sha"]
                or not eligible(fresh, fresh_compare, fresh_refs)):
            continue
        api("/git/refs/heads/" + quote(name, safe="/"), "DELETE")
        report["deleted"].append(name)
    return report


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--execute", action="store_true")
    p.add_argument("--max-deletes", type=int, default=10)
    args = p.parse_args()
    token = os.environ["GITHUB_TOKEN"]
    repo = os.environ["GITHUB_REPOSITORY"]
    def api(path, method="GET"):
        request = Request("https://api.github.com/repos/" + repo + path, method=method,
                          headers={"Authorization": "Bearer " + token,
                                   "Accept": "application/vnd.github+json",
                                   "User-Agent": "katarina-guarded-cleanup"})
        with urlopen(request, timeout=25) as response:
            return json.load(response) if method == "GET" else response.status

    report = cleanup(api, repo, execute=args.execute, max_deletes=args.max_deletes)
    os.makedirs("build/validation", exist_ok=True)
    with open("build/validation/branch-cleanup.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print("PASS_GUARDED_BRANCH_CLEANUP", json.dumps(report))


if __name__ == "__main__":
    main()
