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

    open_heads = set()
    for page in range(1, 21):
        prs = api(f"/pulls?state=open&per_page=100&page={page}")
        open_heads.update(x["head"]["ref"] for x in prs
                          if x.get("head", {}).get("repo", {}).get("full_name") == repo)
        if len(prs) < 100:
            break
    candidates = []
    deleted = []
    for page in range(1, 21):
        branches = api(f"/branches?per_page=100&page={page}")
        for branch in branches:
            name = branch["name"]
            if name == "main":
                continue
            encoded = quote(name, safe="")
            comparison = api("/compare/main..." + encoded)
            if not eligible(branch, comparison, open_heads):
                continue
            candidates.append(name)
            if not args.execute or len(deleted) >= args.max_deletes:
                continue
            # Recheck the branch SHA, protection and ancestry immediately before delete.
            fresh_branch = api("/branches/" + encoded)
            fresh_compare = api("/compare/main..." + encoded)
            if (fresh_branch["commit"]["sha"] != branch["commit"]["sha"]
                    or not eligible(fresh_branch, fresh_compare, open_heads)):
                continue
            api("/git/refs/heads/" + quote(name, safe="/"), "DELETE")
            deleted.append(name)
        if len(branches) < 100:
            break
    os.makedirs("build/validation", exist_ok=True)
    report = {"dry_run": not args.execute, "candidates": candidates,
              "deleted": deleted, "max_deletes": args.max_deletes}
    with open("build/validation/branch-cleanup.json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print("PASS_GUARDED_BRANCH_CLEANUP", json.dumps(report))


if __name__ == "__main__":
    main()
