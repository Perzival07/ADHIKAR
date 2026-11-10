"""Profile view with the same derived properties as lib/core/models/citizen_profile.dart."""
from __future__ import annotations

from typing import Any

from .contract_models import CitizenProfile


def build_context(p: CitizenProfile) -> dict[str, Any]:
    d = p.model_dump()
    d["isFarmer"] = p.occupation == "Farmer"
    d["isSalaried"] = p.occupation == "Salaried"
    d["isArtisan"] = p.occupation == "Artisan / Craftsman"
    d["isStreetVendor"] = p.occupation == "Street Vendor"
    d["isStudent"] = p.occupation == "Student" or p.studentLevel != "None"
    d["isSenior"] = p.age >= 60
    d["isWidow"] = p.gender == "Female" and p.maritalStatus == "Widow"
    d["isLowIncome"] = p.annualIncomeRange in ("< 1 Lakh", "1 - 2.5 Lakh")
    d["hasBplOrAay"] = p.rationCard in ("Antyodaya (AAY)", "BPL", "Priority (PHH)")
    d["isDivyangjan"] = p.disabilityStatus == "40%+ (Divyangjan)"
    d["trade"] = p.artisanTrade if p.artisanTrade else "traditional craftsperson"
    return d
