/** Everything that changes between releases lives here. */
export const site = {
  name: 'MiliControl',
  url: 'https://miliidea.github.io/MiliControl/',
  repo: 'https://github.com/MiliIdea/MiliControl',
  repoPath: 'MiliIdea/MiliControl',
  /** Fallback until the latest DMG's direct link is fetched (see useDownloadURL). */
  download: 'https://github.com/MiliIdea/MiliControl/releases/latest',
  minimumMacOS: 'macOS 13',
} as const

export const asset = (path: string) => `${import.meta.env.BASE_URL}${path}`
