import { CalendarDays, Globe, Grid3x3, LayoutGrid, Music2, ShieldCheck } from 'lucide-react'
import type { ReactNode } from 'react'
import { asset } from '../site'
import { Reveal } from './Reveal'

export function SectionHeading({ eyebrow, title, children, id }: { eyebrow: string; title: ReactNode; children?: ReactNode; id?: string }) {
  return (
    <Reveal className="mx-auto mb-14 max-w-2xl text-center">
      <p className="mb-3 font-mono text-xs font-medium tracking-[0.2em] text-brand-2 uppercase">{eyebrow}</p>
      <h2 id={id} className="text-3xl font-semibold tracking-[-0.03em] text-balance sm:text-4xl md:text-5xl">
        {title}
      </h2>
      {children && <p className="mt-5 text-lg leading-relaxed text-muted text-pretty">{children}</p>}
    </Reveal>
  )
}

const layout = [
  { name: 'Home', desktops: [1, 2] },
  { name: 'Work', desktops: [3, 4, 5] },
  { name: 'Side project', desktops: [6, 7, 8, 9] },
]

export function Strip() {
  return (
    <section aria-labelledby="strip-title" className="border-y border-line bg-surface/40 py-16 md:py-20">
      <div className="container-page grid items-center gap-12 md:grid-cols-2">
        <Reveal>
          <p className="mb-3 font-mono text-xs font-medium tracking-[0.2em] text-brand-2 uppercase">Why MiliControl</p>
          <h2 id="strip-title" className="text-3xl font-semibold tracking-[-0.03em] text-balance sm:text-4xl">
            Nine desktops in a line is a lot of swiping.
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-muted text-pretty">
            Give each part of your life its own row and you’re never more than a couple of slides away. MiliControl decides{' '}
            <em>where</em> to go; macOS does the switch — so it feels exactly like your Mac, only organised.
          </p>
        </Reveal>
        <Reveal delay={0.1}>
          <div className="space-y-6">
            <div>
              <p className="mb-2.5 text-sm text-subtle">macOS</p>
              <div className="flex gap-1.5 overflow-hidden">
                {Array.from({ length: 9 }, (_, i) => (
                  <span key={i} className="grid aspect-[16/10] min-w-0 flex-1 place-items-center rounded-md border border-line bg-raised font-mono text-xs text-subtle">
                    {i + 1}
                  </span>
                ))}
              </div>
            </div>
            <div>
              <p className="mb-2.5 text-sm text-brand-2">With MiliControl</p>
              <div className="space-y-1.5">
                {layout.map((row) => (
                  <div key={row.name} className="flex items-center gap-3">
                    <span className="w-24 shrink-0 text-sm text-muted">{row.name}</span>
                    <div className="grid flex-1 grid-cols-4 gap-1.5">
                      {row.desktops.map((n) => (
                        <span key={n} className={`grid aspect-[16/10] place-items-center rounded-md border font-mono text-xs ${n === 4 ? 'border-brand-2 bg-brand text-white' : 'border-line bg-raised text-subtle'}`}>
                          {n}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  )
}

export function ProductShot() {
  return (
    <section aria-labelledby="shot-title" className="overflow-x-clip py-24 md:py-32">
      <div className="container-page">
        <SectionHeading id="shot-title" eyebrow="The grid view" title="Every desktop, and your day, at a glance">
          Press <kbd className="kbd align-middle">⌃</kbd> <kbd className="kbd align-middle">↑</kbd> for live previews of every desktop and
          fullscreen app, above a dashboard with your calendar, what’s next, a to-do list and a sticky note. Drag desktops
          between rows, click one to go.
        </SectionHeading>
        <Reveal>
          <div className="relative">
            <div aria-hidden className="absolute -inset-x-10 -top-10 bottom-0 bg-[radial-gradient(50%_50%_at_50%_30%,rgb(10_107_255/0.22),transparent)] blur-2xl" />
            <img
              src={asset('screenshot.webp')}
              alt="MiliControl's grid view: a dashboard with a clock, a month calendar with Persian dates, upcoming events, a to-do list and a sticky note, above three rows of desktop previews"
              width={2000}
              height={1293}
              loading="lazy"
              decoding="async"
              className="relative w-full rounded-2xl border border-line-strong shadow-2xl shadow-black/60"
            />
          </div>
        </Reveal>
      </div>
    </section>
  )
}

const features = [
  {
    icon: Grid3x3,
    title: 'Grid navigation',
    body: '⌃⌥ ← → moves within a row, ⌃⌥ ↑ ↓ between rows. Tap to slide instantly, or hold the arrow to see the whole grid and jump anywhere in one slide. Four-finger swipes work too.',
    wide: true,
  },
  {
    icon: LayoutGrid,
    title: 'The grid view',
    body: 'Live previews of every desktop and fullscreen app, with browser profiles (“Chrome · Work”) on each tile.',
  },
  {
    icon: CalendarDays,
    title: 'A calm dashboard',
    body: 'Clock, month calendar with your events, up next, to-dos and a note. Add a second calendar — Persian, Hijri, Hebrew and more.',
  },
  {
    icon: Music2,
    title: 'A living notch',
    body: 'Spotify and Apple Music widen the notch with artwork and a little wave. New Telegram, WhatsApp and Slack messages drop down from it.',
  },
  {
    icon: Globe,
    title: 'Web tabs',
    body: 'Keep chess.com, YouTube, ChatGPT — any site — one click away in the grid view. Pages stay exactly where you left them.',
  },
  {
    icon: ShieldCheck,
    title: 'Light, native and private',
    body: 'A menu-bar app with no Dock icon. Per-desktop Dock visibility, launch at login and automatic updates. Nothing ever leaves your Mac.',
    wide: true,
  },
]

export function Features() {
  return (
    <section aria-labelledby="features-title" id="features" className="scroll-mt-20 pb-24 md:pb-32">
      <div className="container-page">
        <SectionHeading id="features-title" eyebrow="Features" title={<>Small app. Your whole Mac,<br className="hidden sm:block" /> a little calmer.</>} />
        <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {features.map((feature, i) => (
            <Reveal key={feature.title} delay={(i % 4) * 0.06} className={`h-full ${feature.wide ? 'lg:col-span-2' : ''}`}>
              <li className="group h-full rounded-2xl border border-line bg-surface p-6 transition-colors duration-300 hover:border-line-strong hover:bg-raised">
                <feature.icon className="mb-5 size-6 text-brand-2 transition-transform duration-300 group-hover:-translate-y-0.5" aria-hidden />
                <h3 className="mb-2 text-lg font-semibold tracking-tight">{feature.title}</h3>
                <p className="text-[15px] leading-relaxed text-muted">{feature.body}</p>
              </li>
            </Reveal>
          ))}
        </ul>
      </div>
    </section>
  )
}

const shortcuts: { keys: string[][]; what: string }[] = [
  { keys: [['⌃', '⌥', '←'], ['⌃', '⌥', '→']], what: 'Previous / next desktop in the current row' },
  { keys: [['⌃', '⌥', '↑'], ['⌃', '⌥', '↓']], what: 'Previous / next row' },
  { keys: [['Hold the arrow']], what: 'Show the grid · tap arrows to choose · release ⌃⌥ to go' },
  { keys: [['⌃', '↑'], ['⌃', '⌥', 'Space']], what: 'Open the grid view' },
  { keys: [['⌃', '↓'], ['Esc']], what: 'Close the grid view' },
]

export function Shortcuts() {
  return (
    <section aria-labelledby="shortcuts-title" id="shortcuts" className="scroll-mt-20 py-24 md:py-32">
      <div className="container-page max-w-4xl">
        <SectionHeading id="shortcuts-title" eyebrow="Shortcuts" title="Five shortcuts. That’s the whole manual." />
        <Reveal>
          <dl className="divide-y divide-line rounded-2xl border border-line bg-surface">
            {shortcuts.map((shortcut) => (
              <div key={shortcut.what} className="flex flex-col gap-3 px-6 py-5 sm:flex-row sm:items-center sm:justify-between sm:gap-8">
                <dt className="flex flex-wrap items-center gap-2">
                  {shortcut.keys.map((combo, i) => (
                    <span key={i} className="flex items-center gap-1.5">
                      {i > 0 && <span className="mr-0.5 text-sm text-subtle">or</span>}
                      {combo.map((key) => (
                        <kbd key={key} className="kbd">{key}</kbd>
                      ))}
                    </span>
                  ))}
                </dt>
                <dd className="text-muted sm:text-right">{shortcut.what}</dd>
              </div>
            ))}
          </dl>
        </Reveal>
      </div>
    </section>
  )
}
