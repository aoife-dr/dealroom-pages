# client-pages

Client-facing Dealroom pages, served by GitHub Pages. Each page is password-protected with [StatiCrypt](https://github.com/robinmoisson/staticrypt), so this repo only holds encrypted pages. Each page lives in its own folder with a random slug that doesn't name the client, so the URL can't be guessed and the repo doesn't show who the pages are for. The root page is blank, and `robots.txt` and a `noindex` meta keep the pages out of search engines.

Page URLs look like `https://aoife-dr.github.io/client-pages/<slug>/`.

## What's kept on your Mac, never in the repo

Everything that identifies a client or unlocks a page is in `~/.config/client-pages/`:

```
pages.tsv              slug, live URL, source file, last published (one line per page)
<slug>.password        the page's password
<slug>.staticrypt.json the page's salt
```

To find a page's slug and its republish command, look it up in `pages.tsv`:

```bash
column -t -s $'\t' ~/.config/client-pages/pages.tsv
```

Copy a password to send to the client, in a separate message from the link:

```bash
pbcopy < ~/.config/client-pages/<slug>.password
```

Republishing reuses the same password and salt, so the client's password and "Remember me" keep working. If you lose these files, the next publish creates a new password and you'll need to send it again. To change a page's password, delete its `.password` file and republish.

## Republish after editing the source

Run from this folder, with the source file and slug from `pages.tsv`:

```bash
./publish.sh path/to/source.html <slug>
```

The script cleans a copy and leaves your source file alone. It removes the draft bar, the draft CSS, any `<span data-todo>` placeholders and any other `data-todo` attributes, and it adds the `noindex` meta. Then it encrypts the page, commits, pushes and updates `pages.tsv`. The page updates in about a minute. You'll need Node.js; the script runs StatiCrypt 3.5.4 through `npx`.

## Add another client page

1. Make a slug. Use `c-` plus eight random characters, and don't put the client's name in it:

   ```bash
   echo "c-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 8)"
   ```

2. Publish into it. This creates the password and adds the page to `pages.tsv`:

   ```bash
   ./publish.sh path/to/Client-x-Dealroom.html c-k3x9p2ab
   ```

Only encrypted pages go in this repo. Never commit a source file, a cleaned unencrypted copy, or anything naming a client, including commit messages.
