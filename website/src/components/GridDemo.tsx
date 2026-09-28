import { motion } from 'motion/react'
import { useCallback, useEffect, useRef, useState } from 'react'

type Pos = { row: number; col: number }
type Key = 'left' | 'right' | 'up' | 'down'

const rows = [
  { name: 'Home', desktops: ['from-sky-500/70 to-indigo-700/70', 'from-amber-400/60 to-rose-600/60'] },
  { name: 'Work', desktops: ['from-slate-500/60 to-slate-800/70', 'from-violet-500/60 to-fuchsia-800/60', 'from-cyan-500/60 to-blue-800/70'] },
  {
    name: 'Side project',
    desktops: ['from-emerald-500/60 to-teal-800/70', 'from-blue-500/60 to-slate-900/70', 'from-orange-500/60 to-red-800/60', 'from-pink-500/50 to-purple-900/70'],
  },
]

// A scripted tour of the grid for when nobody is touching it.
const tour: Key[] = ['right', 'down', 'right', 'right', 'down', 'right', 'left', 'up', 'left', 'up', 'left', 'down', 'down', 'up', 'up']

const glyph: Record<Key, string> = { left: '←', right: '→', up: '↑', down: '↓' }
const place: Record<Key, string> = { up: 'col-start-2', left: 'col-start-1 row-start-2', down: 'col-start-2 row-start-2', right: 'col-start-3 row-start-2' }

function move({ row, col }: Pos, key: Key): Pos {
  if (key === 'left') return { row, col: Math.max(0, col - 1) }
  if (key === 'right') return { row, col: Math.min(rows[row].desktops.length - 1, col + 1) }
  const next = key === 'up' ? Math.max(0, row - 1) : Math.min(rows.length - 1, row + 1)
  return { row: next, col: Math.min(col, rows[next].desktops.length - 1) }
}

const number = (row: number, col: number) => rows.slice(0, row).reduce((sum, r) => sum + r.desktops.length, 0) + col + 1

/** The hero: MiliControl's grid of desktops, touring itself until you take over with the arrow keys. */
export function GridDemo() {
  const [pos, setPos] = useState<Pos>({ row: 0, col: 0 })
  const [pressed, setPressed] = useState<Key | null>(null)
  const [manual, setManual] = useState(false)
  const step = useRef(0)

  const press = useCallback((key: Key) => {
    setPos((p) => move(p, key))
    setPressed(key)
    window.setTimeout(() => setPressed((k) => (k === key ? null : k)), 260)
  }, [])

  useEffect(() => {
    if (manual || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const timer = window.setInterval(() => press(tour[step.current++ % tour.length]), 1400)
    return () => window.clearInterval(timer)
  }, [manual, press])

  const takeOver = (key: Key) => {
    setManual(true)
    press(key)
  }

  const onKeyDown = (event: React.KeyboardEvent) => {
    const key = ({ ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down' } as const)[event.key as string]
    if (!key) return
    event.preventDefault()
    takeOver(key)
  }

  return (
    <div className="relative">
      <div aria-hidden className="absolute -inset-8 rounded-[2.5rem] bg-[radial-gradient(60%_60%_at_50%_40%,rgb(10_107_255/0.28),transparent)] blur-2xl" />
      <div
        role="application"
        aria-label="Interactive demo: use the arrow keys to move between desktops"
        tabIndex={0}
        onKeyDown={onKeyDown}
        className="relative rounded-[1.4rem] border border-line-strong bg-[#101319]/90 p-4 shadow-2xl shadow-black/60 backdrop-blur sm:p-5"
      >
        <div className="mb-4 flex items-center justify-between">
          <div className="flex gap-1.5" aria-hidden>
            <span className="size-3 rounded-full bg-[#ff5f57]" />
            <span className="size-3 rounded-full bg-[#febc2e]" />
            <span className="size-3 rounded-full bg-[#28c840]" />
          </div>
          <p className="font-mono text-xs text-subtle" aria-live="polite">
            Desktop {number(pos.row, pos.col)} · {rows[pos.row].name}
          </p>
        </div>

        <div className="space-y-3">
          {rows.map((row, r) => (
            <div key={row.name} className={`rounded-xl border p-2.5 transition-colors duration-300 ${r === pos.row ? 'border-line-strong bg-white/[0.045]' : 'border-line bg-white/[0.02]'}`}>
              <p className="mb-2 px-0.5 text-xs font-medium text-muted">{row.name}</p>
              <div className="grid grid-cols-4 gap-2">
                {row.desktops.map((wallpaper, c) => {
                  const current = r === pos.row && c === pos.col
                  return (
                    <button
                      key={c}
                      type="button"
                      tabIndex={-1}
                      aria-label={`Go to desktop ${number(r, c)}`}
                      onClick={() => {
                        setManual(true)
                        setPos({ row: r, col: c })
                      }}
                      className="relative aspect-[16/10] cursor-pointer rounded-lg"
                    >
                      <span className={`absolute inset-0 overflow-hidden rounded-lg bg-gradient-to-br ${wallpaper}`}>
                        <span className="absolute top-[18%] left-[12%] h-[46%] w-[52%] rounded-[3px] bg-white/25 shadow-sm" />
                        <span className="absolute top-[34%] left-[42%] h-[48%] w-[46%] rounded-[3px] bg-black/25 ring-1 ring-white/10" />
                      </span>
                      <span className="absolute top-1 left-1.5 font-mono text-[10px] font-semibold text-white/90">{number(r, c)}</span>
                      {current && (
                        <motion.span
                          layoutId="current-desktop"
                          transition={{ type: 'spring', stiffness: 420, damping: 34 }}
                          className="absolute -inset-[3px] rounded-[10px] border-2 border-white shadow-[0_0_24px_rgb(77_163_255/0.6)]"
                        />
                      )}
                    </button>
                  )
                })}
              </div>
            </div>
          ))}
        </div>

        <div className="mt-5 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-1.5" aria-hidden>
            <span className="kbd">⌃</span>
            <span className="kbd">⌥</span>
          </div>
          <div className="grid grid-cols-3 gap-1.5">
            {(['up', 'left', 'down', 'right'] as const).map((key) => (
              <button
                key={key}
                type="button"
                aria-label={`Move ${key}`}
                onClick={() => takeOver(key)}
                className={`kbd cursor-pointer transition duration-150 ${place[key]} ${
                  pressed === key ? 'translate-y-px border-brand-2 bg-none! bg-brand! text-white shadow-[0_0_18px_rgb(10_107_255/0.7)]' : 'hover:border-white/40'
                }`}
              >
                {glyph[key]}
              </button>
            ))}
          </div>
          <p className="w-full text-xs text-subtle sm:w-auto sm:max-w-[11rem] sm:text-right">
            {manual ? 'You’re driving — every move is a native macOS slide.' : 'Click here and use your arrow keys.'}
          </p>
        </div>
      </div>
    </div>
  )
}
