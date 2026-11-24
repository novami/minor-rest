#!/usr/bin/env python3
"""Kontrola překladů: klíče cs/en, shodné {placeholdery}, použité klíče existují, natvrdo psané texty v UI."""
import glob
import json
import re
import sys

PATH = "App/Localizable.xcstrings"
strings = json.load(open(PATH, encoding="utf-8"))["strings"]
errors, warnings = [], []

for key, val in strings.items():
    loc = val.get("localizations", {})
    for lang in ("cs", "en"):
        if not loc.get(lang, {}).get("stringUnit", {}).get("value"):
            errors.append(f"{key}: chybí překlad {lang}")
    if "cs" in loc and "en" in loc:
        ph = lambda lang: set(re.findall(r"\{(\w+)\}", loc[lang]["stringUnit"]["value"]))
        if ph("cs") != ph("en"):
            errors.append(f"{key}: různé {{placeholdery}} v cs a en")

files = [f for f in glob.glob("**/*.swift", recursive=True) if f.startswith(("App/", "Features/"))]
call = re.compile(r'(?<![\w.])t\("([\w.]+)"')
hard = re.compile(r'\b(?:Text|Button|Label|Toggle|TextField|Picker|Section|Menu)\("(?!\s*"|\\\()([^"]*[A-Za-zÀ-ž]{2}[^"]*)"')
for f in files:
    for no, line in enumerate(open(f, encoding="utf-8"), 1):
        code = line.split("//")[0]
        for key in call.findall(code):
            if key.endswith("."):  # dynamický klíč `t("prefix." + x)`
                if not any(k.startswith(key) for k in strings):
                    errors.append(f"{f}:{no}: žádný klíč s předponou {key}")
            elif key not in strings:
                errors.append(f"{f}:{no}: neznámý klíč {key}")
        if hard.search(code) and "t(" not in code:
            warnings.append(f"{f}:{no}: natvrdo psaný text: {code.strip()[:90]}")

for w in warnings:
    print("varování:", w)
for e in errors:
    print("chyba:", e)
print(f"klíčů: {len(strings)}, chyb: {len(errors)}, varování: {len(warnings)}")
sys.exit(1 if errors else 0)
