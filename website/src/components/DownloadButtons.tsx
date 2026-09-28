import { Download } from 'lucide-react'
import { site } from '../site'
import { useDownloadURL } from '../useDownloadURL'
import { GitHubMark } from './GitHubMark'

export function DownloadButtons({ align = 'start' }: { align?: 'start' | 'center' }) {
  const downloadURL = useDownloadURL()

  return (
    <div className={`flex flex-wrap items-center gap-3 ${align === 'center' ? 'justify-center' : ''}`}>
      <a
        href={downloadURL}
        className="group inline-flex h-12 cursor-pointer items-center gap-2.5 rounded-xl bg-fg px-5 font-semibold text-bg shadow-[0_8px_30px_-8px_rgb(109_130_255/0.6)] transition duration-200 hover:bg-white hover:shadow-[0_10px_40px_-6px_rgb(109_130_255/0.8)]"
      >
        <Download className="size-5 transition-transform duration-200 group-hover:translate-y-0.5" aria-hidden />
        Download for macOS
      </a>
      <a
        href={site.repo}
        className="inline-flex h-12 cursor-pointer items-center gap-2.5 rounded-xl border border-line-strong bg-white/[0.03] px-5 font-semibold text-fg transition duration-200 hover:border-white/40 hover:bg-white/[0.07]"
      >
        <GitHubMark />
        Star on GitHub
      </a>
    </div>
  )
}
