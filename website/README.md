# MiliControl website

The landing page at https://control.mili.today/ — Vite, React, Tailwind CSS and Motion.

```bash
npm install
npm run dev      # http://localhost:5173/
npm run build    # pre-rendered static site in dist/
```

`npm run build` renders the page to static HTML (`scripts/prerender.mjs`) so search engines and link previews
get the full content; the client bundle then hydrates it. Download buttons link to the latest release's DMG
(looked up from the GitHub API, falling back to the releases page); release links live in `src/site.ts`.
It is hosted on Vercel (project root: `website/`). The old GitHub Pages address redirects here (`.github/workflows/pages.yml`).
