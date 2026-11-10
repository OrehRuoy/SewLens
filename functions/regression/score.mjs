import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createGeminiClient } from '../src/gemini.mjs'
import { scoreCases } from '../src/score.mjs'

const directory = dirname(fileURLToPath(import.meta.url))
const manifest = JSON.parse(readFileSync(join(directory, 'manifest.json'), 'utf8'))

function mimeType(name, bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return 'image/jpeg'
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return 'image/png'
  if (name.endsWith('.webp')) return 'image/webp'
  return 'image/jpeg'
}

const cases = manifest.map((item) => {
  const bytes = readFileSync(join(directory, 'photos', item.file))
  return {
    id: item.id,
    design: item.design,
    photo: { mimeType: mimeType(item.file, bytes), data: bytes.toString('base64') },
  }
})

const apiKey = process.env.GEMINI_API_KEY
if (!apiKey) {
  console.error('GEMINI_API_KEY is not set')
  process.exit(1)
}

const score = await scoreCases(cases, createGeminiClient({ apiKey }))
console.log(JSON.stringify({ correct: score.correct, total: score.total, passed: score.passed, details: score.details }, null, 2))
if (!score.passed) process.exit(1)
