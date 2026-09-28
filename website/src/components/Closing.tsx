import { ArrowUpRight, Plus } from 'lucide-react'
import { useState } from 'react'
import { faqs } from '../content'
import { asset, site } from '../site'
import { DownloadButtons } from './DownloadButtons'
import { GitHubMark } from './GitHubMark'
import { Reveal } from './Reveal'
import { SectionHeading } from './Sections'

const steps = [
  { title: 'Download and install', body: 'Open the DMG and drag MiliControl onto Applications. It’s signed with a Developer ID and notarized by Apple.' },
  { title: 'Follow the checklist', body: 'Settings shows a short setup checklist — Accessibility and a couple of Mission Control shortcuts. Keep going until everything is green.' },
  { title: 'Arrange your rows', body: 'Press ⌃↑ to open the grid view, name your rows and drag desktops into them. MiliControl updates itself from then on.' },
]

export function GetStarted() {
  return (
    <section aria-labelledby="start-title" id="get-started" className="scroll-mt-20 py-24 md:py-32">
      <div className="container-page">
        <SectionHeading id="start-title" eyebrow="Get started" title="Set up in about a minute" />
        <ol className="grid gap-5 md:grid-cols-3">
          {steps.map((step, i) => (
            <Reveal key={step.title} delay={i * 0.08} className="h-full">
              <li className="h-full rounded-2xl border border-line bg-surface p-7">
                <span className="mb-6 grid size-10 place-items-center rounded-xl bg-brand/15 font-mono text-sm font-semibold text-brand-2 ring-1 ring-brand/35">
                  {i + 1}
                </span>
                <h3 className="mb-3 text-xl font-semibold tracking-tight">{step.title}</h3>
                <p className="leading-relaxed text-muted">{step.body}</p>
              </li>
            </Reveal>
          ))}
        </ol>
      </div>
    </section>
  )
}

export function FAQ() {
  const [open, setOpen] = useState<number | null>(0)
  return (
    <section aria-labelledby="faq-title" id="faq" className="scroll-mt-20 py-24 md:py-32">
      <div className="container-page max-w-3xl">
        <SectionHeading id="faq-title" eyebrow="FAQ" title="Questions, answered" />
        <div className="divide-y divide-line rounded-2xl border border-line bg-surface">
          {faqs.map((faq, i) => {
            const expanded = open === i
            return (
              <div key={faq.q}>
                <h3>
                  <button
                    type="button"
                    aria-expanded={expanded}
                    aria-controls={`faq-${i}`}
                    onClick={() => setOpen(expanded ? null : i)}
                    className="flex w-full cursor-pointer items-center justify-between gap-6 px-6 py-5 text-left text-[17px] font-medium transition-colors duration-200 hover:text-white"
                  >
                    {faq.q}
                    <Plus className={`size-5 shrink-0 text-muted transition-transform duration-300 ${expanded ? 'rotate-45' : ''}`} aria-hidden />
                  </button>
                </h3>
                {/* Kept in the DOM (hidden) so the answers are part of the static HTML. */}
                <div
                  id={`faq-${i}`}
                  role="region"
                  hidden={!expanded}
                  className="px-6 pb-6 leading-relaxed text-muted"
                >
                  {faq.a}
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}

export function FinalCTA() {
  return (
    <section aria-labelledby="cta-title" className="pb-24 md:pb-32">
      <div className="container-page">
        <Reveal>
          <div className="relative overflow-hidden rounded-3xl border border-line-strong bg-surface px-6 py-16 text-center md:px-16 md:py-20">
            <div aria-hidden className="absolute inset-0 bg-[radial-gradient(60%_80%_at_50%_0%,rgb(10_107_255/0.3),transparent),radial-gradient(40%_60%_at_80%_100%,rgb(247_223_124/0.08),transparent)]" />
            <div className="relative">
              <img src={asset('icon.svg')} alt="" width={80} height={80} loading="lazy" className="mx-auto mb-7 size-20" />
              <h2 id="cta-title" className="text-3xl font-semibold tracking-[-0.03em] text-balance sm:text-5xl">
                Give every part of your day its own row
              </h2>
              <p className="mx-auto mt-5 max-w-xl text-lg text-muted">
                Free and open source, for macOS 13 and later.
              </p>
              <div className="mt-9">
                <DownloadButtons align="center" />
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  )
}

export function Developer() {
  return (
    <section id="developer" aria-labelledby="developer-title" className="scroll-mt-20 pb-24 md:pb-32">
      <div className="container-page">
        <Reveal>
          <a
            href={site.developer.url}
            className="group mx-auto flex max-w-3xl cursor-pointer flex-col items-center gap-6 rounded-3xl border border-line bg-surface p-7 text-center transition-colors duration-300 hover:border-line-strong hover:bg-raised sm:flex-row sm:text-left md:p-8"
          >
            <img
              src={asset('mili-avatar.webp')}
              alt="Chibi Mili riding the Batriders bat"
              width={96}
              height={96}
              loading="lazy"
              className="size-24 shrink-0 rounded-full ring-2 ring-line-strong transition-transform duration-300 group-hover:-rotate-6"
            />
            <div className="min-w-0 flex-1">
              <p className="font-mono text-xs font-medium tracking-[0.2em] text-brand-2 uppercase">Meet the developer</p>
              <h2 id="developer-title" className="mt-2 text-2xl font-semibold tracking-tight">Hi, I’m Mili</h2>
              <p className="mt-2 leading-relaxed text-muted">
                Milad Karimi — mobile & AI engineer and founder of the Batriders studio. I built {site.name}; the rest
                of my toy box is on mili.today.
              </p>
            </div>
            <span className="inline-flex h-11 shrink-0 items-center gap-2 rounded-xl bg-fg px-5 font-semibold text-bg transition-colors duration-200 group-hover:bg-white">
              Visit mili.today
              <ArrowUpRight className="size-4 transition-transform duration-200 group-hover:translate-x-0.5 group-hover:-translate-y-0.5" aria-hidden />
            </span>
          </a>
        </Reveal>
      </div>
    </section>
  )
}

export function Footer() {
  return (
    <footer className="border-t border-line py-10">
      <div className="container-page flex flex-col items-center justify-between gap-5 text-sm text-subtle md:flex-row">
        <p className="flex flex-wrap items-center justify-center gap-x-2.5 gap-y-1 text-center md:justify-start md:text-left">
          <img src={asset('icon.svg')} alt="" width={20} height={20} loading="lazy" className="size-5" />
          <span>{site.name} · Your Mac’s desktops, arranged in rows</span>
          <span>
            · Made by{' '}
            <a href={site.developer.url} className="font-medium text-muted transition-colors hover:text-fg">
              {site.developer.name}
            </a>
          </span>
        </p>
        <nav aria-label="Footer" className="flex flex-wrap items-center justify-center gap-x-6">
          <a href={site.repo} className="inline-flex cursor-pointer items-center gap-2 py-2.5 transition-colors hover:text-fg">
            <GitHubMark className="size-4" /> GitHub
          </a>
          <a href={`${site.repo}/releases`} className="inline-block cursor-pointer py-2.5 transition-colors hover:text-fg">Releases</a>
          <a href={`${site.repo}/blob/main/LICENSE`} className="inline-block cursor-pointer py-2.5 transition-colors hover:text-fg">MIT License</a>
          <a href={site.developer.url} className="inline-block cursor-pointer py-2.5 transition-colors hover:text-fg">Developer</a>
        </nav>
      </div>
    </footer>
  )
}
