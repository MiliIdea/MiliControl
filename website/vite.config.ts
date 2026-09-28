import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// Served from GitHub Pages at https://miliidea.github.io/MiliControl/
export default defineConfig({
  base: '/MiliControl/',
  plugins: [react(), tailwindcss()],
})
