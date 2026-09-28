import { site } from '../site'
import { DownloadButtons } from './DownloadButtons'
import { GridDemo } from './GridDemo'

const facts = ['Free & open source', `${site.minimumMacOS}+`, 'Apple silicon & Intel', 'Signed & notarized']

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pt-32 pb-20 md:pt-40 md:pb-28">
      <Backdrop />
      <div className="container-page relative grid items-center gap-14 lg:grid-cols-[1fr_1.05fr] [&>*]:min-w-0">
        <div>
          <p className="fade-up mb-6 inline-flex items-center gap-2 rounded-full border border-line-strong bg-white/[0.03] px-3.5 py-1.5 text-sm text-muted">
            <span className="size-1.5 rounded-full bg-brand-2 shadow-[0_0_10px_var(--color-brand-2)]" />
            A menu-bar app for macOS desktops
          </p>

          {/* The headline isn't faded in: it's the page's largest paint and must show immediately. */}
          <h1 className="text-5xl leading-[1.04] font-semibold tracking-[-0.035em] text-balance sm:text-6xl lg:text-7xl">
            Your desktops,
            <br />
            <span className="text-gradient">arranged in rows.</span>
          </h1>

          <p style={{ animationDelay: '0.1s' }} className="fade-up mt-6 max-w-xl text-lg leading-relaxed text-muted text-pretty">
            macOS lines your desktops up in one long strip. MiliControl groups them into rows —{' '}
            <strong className="font-medium text-fg">Home</strong>, <strong className="font-medium text-fg">Work</strong>,{' '}
            <strong className="font-medium text-fg">Side project</strong> — and moves you around the grid with macOS’s own
            slides. Plus a calm dashboard, a living notch and your favourite sites, one shortcut away.
          </p>

          <div style={{ animationDelay: '0.2s' }} className="fade-up mt-9">
            <DownloadButtons />
          </div>

          <ul style={{ animationDelay: '0.35s' }} className="fade-up mt-8 flex flex-wrap gap-x-5 gap-y-2 text-sm text-subtle">
            {facts.map((fact) => (
              <li key={fact} className="flex items-center gap-2">
                <span className="size-1 rounded-full bg-subtle" aria-hidden />
                {fact}
              </li>
            ))}
          </ul>
        </div>

        <div style={{ animationDelay: '0.15s' }} className="fade-up">
          <GridDemo />
        </div>
      </div>
    </section>
  )
}

function Backdrop() {
  return (
    <div aria-hidden className="pointer-events-none absolute inset-0">
      <div className="absolute inset-x-0 top-0 h-[42rem] bg-[radial-gradient(50%_60%_at_75%_5%,rgb(77_163_255/0.16),transparent),radial-gradient(45%_55%_at_15%_10%,rgb(10_107_255/0.14),transparent)]" />
      <div className="absolute inset-0 bg-[radial-gradient(rgb(160_170_190/0.14)_1px,transparent_1px)] bg-[size:28px_28px] [mask-image:radial-gradient(60%_50%_at_50%_0%,black,transparent)]" />
    </div>
  )
}
