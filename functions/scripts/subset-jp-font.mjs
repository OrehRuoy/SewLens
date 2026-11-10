/**
 * Writes assets/fonts/NotoSansJP-SewLens.otf: the Noto Sans JP subset the
 * Godot client uses as its fallback font.
 *
 * Coverage: every character in i18n/strings.csv, kana, CJK punctuation,
 * full-width forms, and JIS X 0208 level-1 kanji (for Gemini's explanations).
 *
 *   node scripts/subset-jp-font.mjs <path to NotoSansJP-Regular.otf>
 * Source: https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf
 */
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import subsetFont from 'subset-font'
import { STRINGS_PATH } from './client-catalog.mjs'

const OUTPUT = join(STRINGS_PATH, '../../assets/fonts/NotoSansJP-SewLens.otf')

function range(set, from, to) {
  for (let code = from; code <= to; code++) set.add(String.fromCodePoint(code))
}

export function coverage() {
  const chars = new Set()
  range(chars, 0x20, 0x7e)
  range(chars, 0x3000, 0x303f)
  range(chars, 0x3040, 0x309f)
  range(chars, 0x30a0, 0x30ff)
  range(chars, 0xff00, 0xffef)
  const decoder = new TextDecoder('euc-jp')
  for (let lead = 0xb0; lead <= 0xcf; lead++) {
    for (let trail = 0xa1; trail <= 0xfe; trail++) {
      const text = decoder.decode(Uint8Array.of(lead, trail))
      if (text.length === 1 && text !== '\ufffd') chars.add(text)
    }
  }
  for (const ch of readFileSync(STRINGS_PATH, 'utf8')) {
    if (ch.codePointAt(0) >= 0x20) chars.add(ch)
  }
  return [...chars].join('')
}

async function main(argv) {
  const source = argv[0]
  if (!source) {
    console.error('usage: node scripts/subset-jp-font.mjs <NotoSansJP-Regular.otf>')
    return 1
  }
  const text = coverage()
  const subset = await subsetFont(readFileSync(source), text, { targetFormat: 'sfnt' })
  writeFileSync(OUTPUT, subset)
  console.log(`Wrote ${OUTPUT} (${subset.length} bytes, ${[...text].length} characters)`)
  return 0
}

process.exitCode = await main(process.argv.slice(2))
