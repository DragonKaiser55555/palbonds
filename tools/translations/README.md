# Translation review file

`docs/translations-review.md` is generated from `mod/PalBonds/Scripts/Locale.lua`,
so it always shows exactly what the mod ships. Regenerate it after any change
to the translations (run from the repo root):

```bash
node tools/translations/dump_locale.js mod/PalBonds/Scripts tools/harness > locale.json
python tools/translations/make_review.py locale.json docs/translations-review.md
```

`make_review.py` holds the English explanation of every string; it refuses to
run if a string is added to Locale.lua without one.
