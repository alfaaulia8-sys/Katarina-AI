from __future__ import annotations

import importlib
import json
from pathlib import Path

from katarina.body.component import PassiveStageComponent
from katarina.body.contracts import AuthorityClass, BodyStatus, StageSpec


class BodyRegistryError(RuntimeError):
    pass


class BodyRegistry:
    def __init__(self, repo_root: str | Path) -> None:
        self.repo_root = Path(repo_root)
        self.manifest_dir = self.repo_root / "config" / "stages"

    def load(self) -> tuple[StageSpec, ...]:
        manifests = sorted(self.manifest_dir.glob("stage*.json"))
        specs: list[StageSpec] = []
        for path in manifests:
            obj = json.loads(path.read_text(encoding="utf-8"))
            spec = StageSpec(
                stage=int(obj["stage"]),
                name=str(obj["name"]),
                dependencies=tuple(int(x) for x in obj["dependencies"]),
                authority=AuthorityClass(str(obj["authority"])),
                policy_pending=bool(obj["policy_pending"]),
                windows_required=bool(obj["windows_required"]),
                implementation_module=str(obj["implementation_module"]),
                reference_doc=str(obj["reference_doc"]),
                status=BodyStatus(str(obj["status"])),
                live_risk_ready=bool(obj["live_risk_ready"]),
                live_execution_authority=bool(obj["live_execution_authority"]),
            )
            specs.append(spec)

        stages = [s.stage for s in specs]
        expected = list(range(11, 41))
        if stages != expected:
            raise BodyRegistryError(
                f"expected Stage 11-40 manifests, got {stages}"
            )
        return tuple(specs)

    def validate(self) -> tuple[StageSpec, ...]:
        specs = self.load()
        seen = set(range(1, 11))
        for spec in specs:
            missing = [dep for dep in spec.dependencies if dep not in seen]
            if missing:
                raise BodyRegistryError(
                    f"stage {spec.stage} missing dependencies {missing}"
                )
            ref = self.repo_root / spec.reference_doc
            if not ref.is_file():
                raise BodyRegistryError(
                    f"stage {spec.stage} reference doc missing: {ref}"
                )

            module = importlib.import_module(spec.implementation_module)
            component_cls = getattr(module, "Component", None)
            if component_cls is None:
                raise BodyRegistryError(
                    f"{spec.implementation_module} does not expose Component"
                )
            component = component_cls()
            if not isinstance(component, PassiveStageComponent):
                raise BodyRegistryError(
                    f"stage {spec.stage} component has unexpected base type"
                )
            if component.stage != spec.stage:
                raise BodyRegistryError(
                    f"stage {spec.stage} module stage mismatch"
                )
            if component.live_execution_authority:
                raise BodyRegistryError(
                    f"stage {spec.stage} unexpectedly grants live authority"
                )
            seen.add(spec.stage)
        return specs


__all__ = ("BodyRegistry", "BodyRegistryError")
