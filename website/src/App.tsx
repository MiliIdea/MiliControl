import { MotionConfig } from 'motion/react'
import { FAQ, FinalCTA, Footer, GetStarted } from './components/Closing'
import { Hero } from './components/Hero'
import { Nav } from './components/Nav'
import { NotchSection } from './components/NotchSection'
import { Features, ProductShot, Shortcuts, Strip } from './components/Sections'

export default function App() {
  return (
    <MotionConfig reducedMotion="user">
      <a href="#main" className="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:left-3 focus:z-[60] focus:rounded-lg focus:bg-fg focus:px-4 focus:py-2 focus:text-bg">
        Skip to content
      </a>
      <Nav />
      <main id="main">
        <Hero />
        <Strip />
        <ProductShot />
        <Features />
        <NotchSection />
        <Shortcuts />
        <GetStarted />
        <FAQ />
        <FinalCTA />
      </main>
      <Footer />
    </MotionConfig>
  )
}
