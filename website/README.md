# MiliControl website

The landing page at https://miliidea.github.io/MiliControl/ — Vite, React, Tailwind CSS and Motion.

```bash
npm install
npm run dev      # http://localhost:5173/MiliControl/
npm run build    # pre-rendered static site in dist/
```

`npm run build` renders the page to static HTML (`scripts/prerender.mjs`) so search engines and link previews
get the full content; the client bundle then hydrates it. Download buttons link to the latest release's DMG
(looked up from the GitHub API, falling back to the releases page); release links live in `src/site.ts`.
Pushing changes under `website/` to `main` deploys to GitHub Pages (`.github/workflows/pages.yml`).
