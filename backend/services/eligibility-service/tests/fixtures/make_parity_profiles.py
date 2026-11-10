"""Deterministically generate profiles for Dart<->Python eligibility parity.

    python make_parity_profiles.py            -> parity_profiles.json
    dart run tool/dump_engine_parity.dart <that file> dart_parity.json   (from the repo root)
"""
import itertools
import json
import random
from pathlib import Path

STATES = ["Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana",
          "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya",
          "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
          "Uttar Pradesh", "Uttarakhand", "West Bengal", "Andaman and Nicobar Islands", "Chandigarh",
          "Dadra and Nagar Haveli and Daman and Diu", "Delhi (NCT)", "Jammu and Kashmir", "Ladakh", "Lakshadweep",
          "Puducherry", "All India"]
OCC = ["Citizen", "Farmer", "Student", "Salaried", "Self-Employed", "Artisan / Craftsman", "Street Vendor",
       "Daily Wage / Laborer", "Homemaker", "Senior Citizen", "Unemployed"]
LEVEL = ["None", "School (1-10)", "Post-Matric (11-12/ITI)", "Higher Ed"]
CAT = ["General", "OBC", "SC", "ST", "EWS"]
RATION = ["Antyodaya (AAY)", "BPL", "Priority (PHH)", "APL", "None"]
INCOME = ["< 1 Lakh", "1 - 2.5 Lakh", "2.5 - 5 Lakh", "> 5 Lakh"]
DISAB = ["None", "< 40%", "40%+ (Divyangjan)"]
MARITAL = ["Single", "Married", "Widow", "Divorced"]
GENDER = ["Male", "Female", "Other"]
TRADES = ["", "Carpenter", "Potter", "Weaver"]


def rand_profile(r: random.Random) -> dict:
    gender = r.choice(GENDER)
    occ = r.choice(OCC)
    return {
        "state": r.choice(STATES), "district": r.choice(["", "Lucknow"]), "age": r.choice([5, 16, 17, 18, 19, 21, 22, 24, 25, 28, 30, 35, 40, 41, 45, 55, 60, 61, 65, 70, 75, 80]),
        "gender": gender, "maritalStatus": r.choice(MARITAL), "occupation": occ,
        "landHoldingAcres": r.choice([0, 0, 0.5, 2, 5.5]) if occ == "Farmer" else r.choice([0, 0, 1]),
        "artisanTrade": r.choice(TRADES) if occ.startswith("Artisan") else "",
        "studentLevel": r.choice(LEVEL), "socialCategory": r.choice(CAT), "rationCard": r.choice(RATION),
        "annualIncomeRange": r.choice(INCOME), "disabilityStatus": r.choice(DISAB), "hasGirlChildUnder10": r.choice([True, False]),
    }


def base(**kw) -> dict:
    p = {"state": "Uttar Pradesh", "district": "", "age": 35, "gender": "Male", "maritalStatus": "Married", "occupation": "Citizen",
         "landHoldingAcres": 0, "artisanTrade": "", "studentLevel": "None", "socialCategory": "General", "rationCard": "None",
         "annualIncomeRange": "1 - 2.5 Lakh", "disabilityStatus": "None", "hasGirlChildUnder10": False}
    p.update(kw)
    return p


def curated() -> list[dict]:
    out = [
        base(state="Maharashtra", gender="Female", age=30, annualIncomeRange="< 1 Lakh"),
        base(state="West Bengal", gender="Female", age=21, occupation="Student", studentLevel="Higher Ed"),
        base(state="West Bengal", gender="Female", age=28, occupation="Homemaker"),
        base(state="Odisha", gender="Female", age=40, annualIncomeRange="< 1 Lakh"),
        base(state="Telangana", gender="Female", age=33, rationCard="BPL"),
        base(state="Rajasthan", age=44),
        base(state="Assam", gender="Female", age=26, annualIncomeRange="< 1 Lakh"),
        base(occupation="Farmer", landHoldingAcres=3.0), base(occupation="Farmer", landHoldingAcres=0),
        base(gender="Female", maritalStatus="Widow", age=62, rationCard="BPL"),
        base(disabilityStatus="40%+ (Divyangjan)", age=25, rationCard="AAY" if False else "Antyodaya (AAY)"),
        base(occupation="Artisan / Craftsman", artisanTrade="Potter"), base(occupation="Street Vendor", age=29),
        base(age=72), base(occupation="Salaried", age=35, annualIncomeRange="> 5 Lakh"),
        base(hasGirlChildUnder10=True, state="Gujarat"), base(state="Punjab", socialCategory="SC", gender="Female", age=30),
        base(state="Delhi (NCT)", gender="Female", age=30), base(state="Karnataka", age=25, gender="Female", annualIncomeRange="< 1 Lakh"),
        base(state="Delhi (NCT)", occupation="Student", studentLevel="Higher Ed", socialCategory="SC"),
        base(state="Delhi (NCT)", occupation="Student", studentLevel="Higher Ed", annualIncomeRange="> 5 Lakh"),
        base(state="Delhi", occupation="Student", studentLevel="Higher Ed", socialCategory="OBC"),
        base(state="All India"), base(state="All India", occupation="Student", studentLevel="Higher Ed", socialCategory="SC", annualIncomeRange="< 1 Lakh"),
    ]
    for st, g, a in itertools.product(["Bihar", "Tamil Nadu", "Madhya Pradesh", "Chhattisgarh", "Uttar Pradesh"], ["Male", "Female"], [17, 22, 45]):
        out.append(base(state=st, gender=g, age=a, annualIncomeRange="< 1 Lakh"))
    return out


if __name__ == "__main__":
    r = random.Random(20261110)
    profiles = curated() + [rand_profile(r) for _ in range(380)]
    Path(__file__).with_name("parity_profiles.json").write_text(json.dumps(profiles, indent=1))
    print(len(profiles), "profiles")
