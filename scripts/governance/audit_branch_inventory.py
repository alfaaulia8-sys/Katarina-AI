"""Read-only GitHub branch classification; never merge, delete, or run broker code."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import quote

def classify(compare: dict) -> str:
    ahead = compare.get("ahead_by")
    behind = compare.get("behind_by")
    if not isinstance(ahead, int) or not isinstance(behind, int):
        return "REVIEW_UNKNOWN"
    if ahead == 0:
        return "PRUNE_CANDIDATE_ALREADY_CONTAINED"
    return "REVIEW_UNMERGED_COMMITS"

def inventory(repo: str, token: str) -> dict:
    if "/" not in repo or not token:
        raise ValueError("repository_and_token_required")
    def get(path):
        req = Request("https://api.github.com/repos/" + repo + path,
                      headers={"Authorization": "Bearer " + token,
                               "Accept": "application/vnd.github+json",
                               "User-Agent": "katarina-branch-inventory"})
        with urlopen(req, timeout=25) as response:
            return json.load(response)
    branches = []
    for page in range(1, 21):
        items = get(f"/branches?per_page=100&page={page}")
        branches.extend(items)
        if len(items) < 100:
            break
    result = []
    for item in branches:
        name = item["name"]
        if name == "main":
            continue
        comparison = get("/compare/main..." + quote(name, safe=""))
        result.append({"branch": name, "classification": classify(comparison),
                       "ahead_by": comparison.get("ahead_by"),
                       "behind_by": comparison.get("behind_by"),
                       "protected": item.get("protected", False)})
    return {"source": "GITHUB_API_READ_ONLY", "classification": result,
            "branches_examined": len(result), "branches_deleted": 0,
            "branches_merged": 0, "live_execution_enabled": False}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--output", default="build/validation/branch-inventory.json")
    args = parser.parse_args()
    report = inventory(args.repo, os.environ.get("GITHUB_TOKEN", ""))
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("PASS_BRANCH_INVENTORY_READ_ONLY", report["branches_examined"])
if __name__ == "__main__":
    main()
