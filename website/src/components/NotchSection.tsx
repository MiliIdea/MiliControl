import { NotchDemo } from './NotchDemo'
import { Reveal } from './Reveal'

const points = [
  ['Now playing', 'Spotify or Apple Music widens the notch with the artwork and a little wave.'],
  ['Full player', 'Hover it for artwork, progress and playback controls.'],
  ['Messages', 'New Telegram, WhatsApp and Slack messages drop down for a few seconds.'],
  ['No notch?', 'Other displays get the same player as a slim pill at the top of the screen.'],
]

export function NotchSection() {
  return (
    <section aria-labelledby="notch-title" id="notch" className="scroll-mt-20 border-y border-line bg-surface/40 py-24 md:py-32">
      <div className="container-page grid items-center gap-14 lg:grid-cols-2 [&>*]:min-w-0">
        <Reveal>
          <p className="mb-3 font-mono text-xs font-medium tracking-[0.2em] text-brand-2 uppercase">The notch</p>
          <h2 id="notch-title" className="text-3xl font-semibold tracking-[-0.03em] text-balance sm:text-4xl md:text-5xl">
            That black bar finally does something.
          </h2>
          <dl className="mt-10 grid gap-6 sm:grid-cols-2">
            {points.map(([title, body]) => (
              <div key={title}>
                <dt className="mb-1.5 font-semibold">{title}</dt>
                <dd className="text-[15px] leading-relaxed text-muted">{body}</dd>
              </div>
            ))}
          </dl>
        </Reveal>
        <Reveal delay={0.1}>
          <NotchDemo />
        </Reveal>
      </div>
    </section>
  )
}
