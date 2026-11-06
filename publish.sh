#!/usr/bin/env bash
# Clean a draft client page, password-protect it with StatiCrypt and publish it
# to <slug-folder>/index.html.
#
#   ./publish.sh <source.html> <slug-folder>
#
# Clean-up (the source file is never modified):
#   - removes the <div class="draftbar">…</div> banner
#   - removes the CSS from "/* Draft placeholders: … */" through the last .draftbar rule
#   - deletes every <span data-todo="…">…</span> placeholder, text included
#   - strips data-todo="…" from any other element, keeping the element
#   - adds <meta name="robots" content="noindex, nofollow"> to <head>
#
# Encryption: the cleaned page only ever exists in a temp folder; the repo gets
# the encrypted page. Each slug's password and salt live outside the repo in
# ~/.config/client-pages/ (created on first publish, reused after, so the
# password and "Remember me" survive republishing). Slugs carry no client name;
# which source file maps to which slug is recorded there in pages.tsv.
#
# Then commits the folder and pushes to main.
set -euo pipefail

STATICRYPT="staticrypt@3.5.4"
SECRETS="$HOME/.config/client-pages"

if [ $# -ne 2 ]; then
  echo "usage: $0 <source.html> <slug-folder>" >&2
  exit 1
fi

src="$1"
slug="${2%/}"
repo="$(cd "$(dirname "$0")" && pwd)"

[ -f "$src" ] || { echo "source not found: $src" >&2; exit 1; }
case "$slug" in
  */*|.*|"") echo "slug-folder must be a single folder name, e.g. c-x7k2q9ab" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/clean"
clean="$tmp/clean/index.html"

python3 -I - "$src" "$clean" <<'PY'
import re, sys

src, out = sys.argv[1], sys.argv[2]
s = open(src, encoding="utf-8").read()

def sub(pattern, repl, text, flags=re.S):
    return re.subn(pattern, repl, text, flags=flags)

# Draft banner at the top of <body>
s, n_bar = sub(r'[ \t]*<div class="draftbar">.*?</div>[ \t]*\n?', "", s)

# Draft CSS: from the marker comment through the last line containing a .draftbar rule
s, n_css = sub(
    r'[ \t]*/\* Draft placeholders: remove this block before sending \*/[^\n]*\n'
    r'(?:[^\n]*\n)*?'
    r'(?:[^\n]*\.draftbar[^\n]*\n)(?![^\n]*\.draftbar)',
    "", s)

# Placeholder spans, text and all
s, n_span = sub(r'<span\b[^>]*\sdata-todo="[^"]*"[^>]*>.*?</span>', "", s)

# Any remaining data-todo attributes
s, n_attr = sub(r'\s+data-todo="[^"]*"', "", s)

# noindex, once
n_meta = 0
if not re.search(r'<meta\s+name="robots"', s, re.I):
    s, n_meta = re.subn(r'(<head[^>]*>)', r'\1\n<meta name="robots" content="noindex, nofollow">', s, count=1, flags=re.I)

left = [k for k in ("draftbar", "data-todo", "Draft placeholders") if k in s]
if left:
    sys.exit(f"clean-up incomplete, still found: {', '.join(left)}")

open(out, "w", encoding="utf-8").write(s)
print(f"removed: draftbar div {n_bar}, draft CSS {n_css}, todo spans {n_span}, "
      f"other data-todo attrs {n_attr}; added robots meta {n_meta}")
PY

# Password and salt for this slug, kept outside the repo
mkdir -p "$SECRETS" && chmod 700 "$SECRETS"
pwfile="$SECRETS/$slug.password"
if [ ! -s "$pwfile" ]; then
  # Four groups of four, e.g. k7mp-3xra-...: lowercase only, and no lookalikes
  # (0/o, 1/l/i), so it survives being read aloud or typed. About 79 bits.
  (umask 077; python3 -I -c '
import secrets
abc = "abcdefghjkmnpqrstuvwxyz23456789"
print("-".join("".join(secrets.choice(abc) for _ in range(4)) for _ in range(4)), end="")
' > "$pwfile")
  echo "new password created: $pwfile"
fi

mkdir -p "$repo/$slug"
# StatiCrypt prefixes "./" to the config path, so run it from the secrets folder
(cd "$SECRETS" && STATICRYPT_PASSWORD="$(cat "$pwfile")" npx -y "$STATICRYPT" "$clean" \
  --config "$slug.staticrypt.json" \
  --directory "$tmp/enc" \
  --remember 30 \
  --template-title "Dealroom" \
  --template-instructions "Enter the password Dealroom sent you to open this page." \
  --template-button "Open" \
  --template-remember "Remember me on this device for 30 days" \
  --template-error "That password didn't work." \
  --template-color-primary "#3C5BFF" \
  --template-color-secondary "#001234" >/dev/null)

# The password screen doesn't carry the source <head>, so add noindex to it too
python3 -I - "$tmp/enc/index.html" "$repo/$slug/index.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
if "staticrypt" not in s:
    sys.exit("encrypted output looks wrong; not publishing")
if not re.search(r'<meta\s+name="robots"', s, re.I):
    s = re.sub(r'(<head[^>]*>)', r'\1\n<meta name="robots" content="noindex, nofollow">', s, count=1, flags=re.I)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY

cd "$repo"
git add -- "$slug/index.html"
if git diff --cached --quiet; then
  echo "no changes to publish"
else
  git commit -q -m "Publish $slug"
  git push -q origin main
  echo "pushed $slug"
fi

owner="$(git remote get-url origin | sed -E 's#.*github.com[:/]([^/]+)/.*#\1#')"
name="$(basename -s .git "$(git remote get-url origin)")"
url="https://$owner.github.io/$name/$slug/"

# Local record of slug -> source, kept out of the repo
srcabs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
touch "$SECRETS/pages.tsv"
grep -v "^$slug	" "$SECRETS/pages.tsv" > "$tmp/pages.tsv" || true
printf '%s\t%s\t%s\t%s\n' "$slug" "$url" "$srcabs" "$(date +%Y-%m-%d)" >> "$tmp/pages.tsv"
sort "$tmp/pages.tsv" > "$SECRETS/pages.tsv"

echo "live in about a minute: $url"
echo "copy the password with: pbcopy < \"$pwfile\""
