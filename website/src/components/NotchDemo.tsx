import { AnimatePresence, motion } from 'motion/react'
import { MessageCircle, Pause, SkipBack, SkipForward } from 'lucide-react'
import { useEffect, useState } from 'react'

type State = 'idle' | 'playing' | 'player' | 'message'
const cycle: { state: State; ms: number }[] = [
  { state: 'idle', ms: 1600 },
  { state: 'playing', ms: 2600 },
  { state: 'player', ms: 3200 },
  { state: 'playing', ms: 1600 },
  { state: 'message', ms: 3000 },
]

const size: Record<State, { width: number; height: number; radius: number }> = {
  idle: { width: 190, height: 32, radius: 12 },
  playing: { width: 290, height: 32, radius: 12 },
  player: { width: 360, height: 150, radius: 28 },
  message: { width: 360, height: 92, radius: 26 },
}

function Wave() {
  return (
    <span className="wave flex h-3.5 items-center gap-[3px]" aria-hidden>
      {[0, 0.2, 0.1, 0.3].map((delay, i) => (
        <span key={i} style={{ animationDelay: `${delay}s` }} className="h-full w-[3px] rounded-full bg-brand-2" />
      ))}
    </span>
  )
}

const Artwork = ({ className }: { className: string }) => (
  <span className={`shrink-0 bg-gradient-to-br from-rose-400 via-fuchsia-500 to-indigo-600 ${className}`} aria-hidden />
)

/** A MacBook's menu bar with MiliControl's notch cycling through its states. */
export function NotchDemo() {
  const [index, setIndex] = useState(1)
  const state = cycle[index].state

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const timer = window.setTimeout(() => setIndex((i) => (i + 1) % cycle.length), cycle[index].ms)
    return () => window.clearTimeout(timer)
  }, [index])

  const { width, height, radius } = size[state]
  const fade = { initial: { opacity: 0 }, animate: { opacity: 1, transition: { delay: 0.15 } }, exit: { opacity: 0, transition: { duration: 0.1 } } }

  return (
    <div aria-hidden className="relative h-[19rem] overflow-hidden rounded-2xl border border-line-strong bg-[linear-gradient(160deg,#1e3a6b_0%,#10213f_40%,#0b0d12_100%)] shadow-2xl shadow-black/60">
      <div className="absolute inset-x-0 top-0 flex h-8 items-center justify-between bg-black/30 px-4 text-[11px] font-medium text-white/80 backdrop-blur">
        <span className="flex gap-4"><span>Finder</span><span className="hidden sm:inline">File</span><span className="hidden sm:inline">Edit</span></span>
        <span>Mon 9:41</span>
      </div>
      <motion.div
        animate={{ width, height, borderBottomLeftRadius: radius, borderBottomRightRadius: radius }}
        transition={{ type: 'spring', stiffness: 260, damping: 26 }}
        className="absolute top-0 left-1/2 max-w-[calc(100%-1.5rem)] -translate-x-1/2 overflow-hidden bg-black shadow-[0_10px_40px_rgb(0_0_0/0.5)]"
      >
        <AnimatePresence mode="popLayout">
          {state === 'playing' && (
            <motion.div key="playing" {...fade} className="flex h-8 items-center justify-between px-3">
              <Artwork className="size-5 rounded" />
              <Wave />
            </motion.div>
          )}
          {state === 'player' && (
            <motion.div key="player" {...fade} className="flex h-full flex-col justify-end gap-3 px-5 pb-4">
              <div className="flex items-center gap-3">
                <Artwork className="size-14 rounded-xl" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-semibold text-white">Midnight Drive</p>
                  <p className="truncate text-xs text-white/60">The Rows</p>
                </div>
                <Wave />
              </div>
              <div className="h-1 overflow-hidden rounded-full bg-white/15">
                <motion.div initial={{ width: '30%' }} animate={{ width: '48%' }} transition={{ duration: 3, ease: 'linear' }} className="h-full bg-white/80" />
              </div>
              <div className="flex justify-center gap-7 text-white">
                <SkipBack className="size-4 fill-current" />
                <Pause className="size-4 fill-current" />
                <SkipForward className="size-4 fill-current" />
              </div>
            </motion.div>
          )}
          {state === 'message' && (
            <motion.div key="message" {...fade} className="flex h-full items-end gap-3 px-5 pb-4">
              <span className="grid size-10 shrink-0 place-items-center rounded-full bg-sky-500 text-white">
                <MessageCircle className="size-5" />
              </span>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-white">Sara</p>
                <p className="truncate text-xs text-white/70">Standup moved to 10:30 — see you there!</p>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
      <div className="absolute inset-x-6 bottom-6 grid grid-cols-3 gap-3 opacity-60">
        <span className="h-20 rounded-lg bg-white/10" />
        <span className="col-span-2 h-20 rounded-lg bg-white/[0.06]" />
      </div>
    </div>
  )
}
