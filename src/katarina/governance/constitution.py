from __future__ import annotations
from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path

@dataclass(frozen=True, slots=True)
class ConstitutionCheck:
    valid: bool
    digest: str
    reason: str

class ConstitutionGuard:
    FORBIDDEN_MUTATION_TARGETS=("KATARINA_CONSTITUTION.md","hard_risk","execution_authority")
    def digest(self, path: str|Path) -> str:
        return sha256(Path(path).read_bytes()).hexdigest()
    def verify(self, path: str|Path, expected_sha256: str) -> ConstitutionCheck:
        d=self.digest(path); return ConstitutionCheck(d==expected_sha256,d,"match" if d==expected_sha256 else "constitution_changed")
    def proposed_paths_allowed(self, paths: list[str]) -> bool:
        return all(not any(x in p for x in self.FORBIDDEN_MUTATION_TARGETS) for p in paths)
