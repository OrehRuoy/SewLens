import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { designs as freesewingDesigns, measurements as freesewingMeasurements } from '@freesewing/i18n'
import { fromMillimetres, LOCALES, normalizeLocale } from './units.mjs'

const directory = join(dirname(fileURLToPath(import.meta.url)), '../i18n')

export const catalogs = Object.fromEntries(
  LOCALES.map((locale) => [locale, JSON.parse(readFileSync(join(directory, `${locale}.json`), 'utf8'))])
)

const PART_TOKENS = [
  'interfacing',
  'undersleeve',
  'topsleeve',
  'waistband',
  'binding',
  'facing',
  'lining',
  'sleeve',
  'collar',
  'pocket',
  'front',
  'back',
  'hood',
  'yoke',
  'brim',
  'skirt',
  'gusset',
  'cuff',
  'side',
  'band',
  'top',
  'hem',
  'neck',
  'loop',
  'tail',
  'tip',
]

export function translate(locale, key) {
  const language = catalogs[locale] ? locale : normalizeLocale(locale)
  if (language === 'en' && key.startsWith('measurements.')) {
    const name = key.slice('measurements.'.length)
    if (freesewingMeasurements[name]) return freesewingMeasurements[name]
  }
  if (language === 'en' && key.startsWith('designs.')) {
    const name = key.slice('designs.'.length)
    if (freesewingDesigns[name]?.t) return freesewingDesigns[name].t
  }
  const [group, leaf] = key.split('.')
  const value = catalogs[language]?.[group]?.[leaf]
  if (typeof value === 'string' && value.length) return value
  return `{{missing:${key}}}`
}

export function pieceLabel(locale, partName) {
  const tail = String(partName).split('.').pop() || String(partName)
  const lower = tail.toLowerCase()
  for (const token of PART_TOKENS) {
    if (lower.includes(token)) return translate(locale, `parts.${token}`)
  }
  return tail
}

export function uiLabels(locale) {
  const labels = {}
  for (const key of Object.keys(catalogs.en.ui)) labels[key] = translate(locale, `ui.${key}`)
  return labels
}

export function measurementLabel(locale, name) {
  return translate(locale, `measurements.${name}`)
}

const CUTS = {
  en: {
    plain: 'Cut {n}',
    fold: 'Cut {n} on fold',
    mirrored: 'Cut {n} mirrored',
    bias: 'Cut {n} on the bias',
    mirroredFold: 'Cut {n} mirrored on fold',
  },
  de: {
    plain: '{n} schneiden',
    fold: '{n} im Bruch schneiden',
    mirrored: '{n} gespiegelt schneiden',
    bias: '{n} im Schrägschnitt schneiden',
    mirroredFold: '{n} gespiegelt im Bruch schneiden',
  },
  fr: {
    plain: 'Couper {n}',
    fold: 'Couper {n} au pli',
    mirrored: 'Couper {n} en miroir',
    bias: 'Couper {n} dans le biais',
    mirroredFold: 'Couper {n} en miroir au pli',
  },
  es: {
    plain: 'Cortar {n}',
    fold: 'Cortar {n} al doblez',
    mirrored: 'Cortar {n} en espejo',
    bias: 'Cortar {n} al sesgo',
    mirroredFold: 'Cortar {n} en espejo al doblez',
  },
  'pt-BR': {
    plain: 'Cortar {n}',
    fold: 'Cortar {n} na dobra',
    mirrored: 'Cortar {n} espelhado',
    bias: 'Cortar {n} no viés',
    mirroredFold: 'Cortar {n} espelhado na dobra',
  },
  ja: {
    plain: '{n}枚裁つ',
    fold: '折り山で{n}枚裁つ',
    mirrored: '左右対称で{n}枚裁つ',
    bias: 'バイアスで{n}枚裁つ',
    mirroredFold: '折り山で左右対称に{n}枚裁つ',
  },
  it: {
    plain: 'Tagliare {n}',
    fold: 'Tagliare {n} sulla piega',
    mirrored: 'Tagliare {n} a specchio',
    bias: 'Tagliare {n} in sbieco',
    mirroredFold: 'Tagliare {n} a specchio sulla piega',
  },
  nl: {
    plain: '{n} knippen',
    fold: '{n} op de vouw knippen',
    mirrored: '{n} gespiegeld knippen',
    bias: '{n} op de bias knippen',
    mirroredFold: '{n} gespiegeld op de vouw knippen',
  },
}

/** "Cut 1 on fold", "Cut 2 mirrored", and the plain count, in the locale. */
export function cutCountPhrase(locale, instruction = {}) {
  const language = languageOf(locale)
  const table = CUTS[language] || CUTS.en
  const count = Number(instruction.cut)
  const n = Number.isInteger(count) && count > 0 ? count : 1
  let template = table.plain
  if (instruction.onFold && n > 1 && !instruction.identical) template = table.mirroredFold
  else if (instruction.onFold) template = table.fold
  else if (instruction.onBias) template = table.bias
  else if (n > 1 && !instruction.identical) template = table.mirrored
  return template.replaceAll('{n}', String(n))
}

export function cutWord(locale) {
  const language = languageOf(locale)
  return ANNOTATIONS[language]?.cut || ANNOTATIONS.en.cut
}

/** Cutting lines for every drafted part, including parts titled before addCut. */
export function cutLinesFromStore(store, locale) {
  const cutlist = store?.get?.('cutlist') || {}
  const lines = []
  for (const [part, entry] of Object.entries(cutlist)) {
    if (!entry || typeof entry !== 'object') continue
    const onFoldPart = Array.isArray(entry.cutOnFold)
    const phrases = []
    for (const rows of Object.values(entry.materials || {})) {
      if (!Array.isArray(rows)) continue
      for (const row of rows) {
        phrases.push(cutCountPhrase(locale, { ...row, onFold: Boolean(row.onFold) || onFoldPart }))
      }
    }
    if (!phrases.length && onFoldPart) phrases.push(cutCountPhrase(locale, { cut: 1, onFold: true }))
    if (!phrases.length) continue
    lines.push({ part, text: [...new Set(phrases)].join(', '), cutWord: cutWord(locale) })
  }
  return lines
}

export function formatMeasurement(locale, name, mm, units, degree = false) {
  const label = measurementLabel(locale, name)
  if (degree) return `${label}: ${Math.round(mm * 10) / 10}°`
  const value = fromMillimetres(mm, units)
  const unit = units === 'imperial' ? 'in' : 'cm'
  return `${label}: ${value} ${unit}`
}

const ANNOTATIONS = {
  en: {
    cut: 'Cut',
    from: 'from',
    fabric: 'fabric',
    lining: 'lining',
    interfacing: 'interfacing',
    canvas: 'canvas',
    various: 'various',
    mirrored: 'mirrored',
    onFold: 'on the fold',
    onBias: 'on the bias',
    onFoldAndBias: 'on the fold and on the bias',
    noName: 'Unnamed',
    noVersion: 'no version',
    includeSeamAllowance: 'This pattern includes seam allowance',
    theWhiteInsideOfThisBoxShouldMeasure: 'The white inside of this box should measure',
    theBlackOutsideOfThisBoxShouldMeasure: 'The black outside of this box should measure',
    supportFreeSewingBecomeAPatron: 'Support FreeSewing. Become a patron',
  },
  de: {
    cut: 'Schneiden',
    from: 'aus',
    fabric: 'Stoff',
    lining: 'Futter',
    interfacing: 'Einlage',
    canvas: 'Einlagestoff',
    various: 'Verschiedenes',
    mirrored: 'gespiegelt',
    onFold: 'im Bruch',
    onBias: 'im Schrägschnitt',
    onFoldAndBias: 'im Bruch und im Schrägschnitt',
    noName: 'Ohne Namen',
    noVersion: 'ohne Version',
    includeSeamAllowance: 'Dieses Schnittmuster enthält Nahtzugabe',
    theWhiteInsideOfThisBoxShouldMeasure: 'Das weiße Innere dieses Kastens sollte messen',
    theBlackOutsideOfThisBoxShouldMeasure: 'Das schwarze Äußere dieses Kastens sollte messen',
    supportFreeSewingBecomeAPatron: 'Unterstütze FreeSewing und werde Förderer',
  },
  fr: {
    cut: 'Couper',
    from: 'dans',
    fabric: 'tissu',
    lining: 'doublure',
    interfacing: 'entoilage',
    canvas: 'toile',
    various: 'divers',
    mirrored: 'en miroir',
    onFold: 'sur le pli',
    onBias: 'dans le biais',
    onFoldAndBias: 'sur le pli et dans le biais',
    noName: 'Sans nom',
    noVersion: 'sans version',
    includeSeamAllowance: 'Ce patron comprend la marge de couture',
    theWhiteInsideOfThisBoxShouldMeasure: "L'intérieur blanc de ce cadre doit mesurer",
    theBlackOutsideOfThisBoxShouldMeasure: "L'extérieur noir de ce cadre doit mesurer",
    supportFreeSewingBecomeAPatron: 'Soutenez FreeSewing. Devenez mécène',
  },
  es: {
    cut: 'Cortar',
    from: 'de',
    fabric: 'tela',
    lining: 'forro',
    interfacing: 'entretela',
    canvas: 'entretela firme',
    various: 'varios',
    mirrored: 'en espejo',
    onFold: 'al lomo',
    onBias: 'al bies',
    onFoldAndBias: 'al lomo y al bies',
    noName: 'Sin nombre',
    noVersion: 'sin versión',
    includeSeamAllowance: 'Este patrón incluye margen de costura',
    theWhiteInsideOfThisBoxShouldMeasure: 'El interior blanco de este recuadro debe medir',
    theBlackOutsideOfThisBoxShouldMeasure: 'El exterior negro de este recuadro debe medir',
    supportFreeSewingBecomeAPatron: 'Apoya a FreeSewing. Hazte mecenas',
  },
  'pt-BR': {
    cut: 'Cortar',
    from: 'de',
    fabric: 'tecido',
    lining: 'forro',
    interfacing: 'entretela',
    canvas: 'entretela firme',
    various: 'vários',
    mirrored: 'espelhado',
    onFold: 'na dobra',
    onBias: 'no viés',
    onFoldAndBias: 'na dobra e no viés',
    noName: 'Sem nome',
    noVersion: 'sem versão',
    includeSeamAllowance: 'Este molde inclui margem de costura',
    theWhiteInsideOfThisBoxShouldMeasure: 'O interior branco desta caixa deve medir',
    theBlackOutsideOfThisBoxShouldMeasure: 'O exterior preto desta caixa deve medir',
    supportFreeSewingBecomeAPatron: 'Apoie o FreeSewing. Torne-se um apoiador',
  },
  ja: {
    cut: '裁断',
    from: 'から',
    fabric: '表地',
    lining: '裏地',
    interfacing: '接着芯',
    canvas: '芯地',
    various: 'その他',
    mirrored: '左右反転',
    onFold: '折り山で',
    onBias: 'バイアスで',
    onFoldAndBias: '折り山とバイアスで',
    noName: '名称なし',
    noVersion: '版なし',
    includeSeamAllowance: 'この型紙には縫い代が含まれます',
    theWhiteInsideOfThisBoxShouldMeasure: 'この枠の白い内側のサイズ',
    theBlackOutsideOfThisBoxShouldMeasure: 'この枠の黒い外側のサイズ',
    supportFreeSewingBecomeAPatron: 'FreeSewingを支援する',
  },
  it: {
    cut: 'Tagliare',
    from: 'da',
    fabric: 'tessuto',
    lining: 'fodera',
    interfacing: 'interfodera',
    canvas: 'tela',
    various: 'vari',
    mirrored: 'a specchio',
    onFold: 'sulla piega',
    onBias: 'in sbieco',
    onFoldAndBias: 'sulla piega e in sbieco',
    noName: 'Senza nome',
    noVersion: 'senza versione',
    includeSeamAllowance: 'Questo cartamodello include il margine di cucitura',
    theWhiteInsideOfThisBoxShouldMeasure: "L'interno bianco di questo riquadro deve misurare",
    theBlackOutsideOfThisBoxShouldMeasure: "L'esterno nero di questo riquadro deve misurare",
    supportFreeSewingBecomeAPatron: 'Sostieni FreeSewing. Diventa un sostenitore',
  },
  nl: {
    cut: 'Knip',
    from: 'uit',
    fabric: 'stof',
    lining: 'voering',
    interfacing: 'vlieseline',
    canvas: 'canvas',
    various: 'overig',
    mirrored: 'gespiegeld',
    onFold: 'op de vouw',
    onBias: 'op de bias',
    onFoldAndBias: 'op de vouw en op de bias',
    noName: 'Zonder naam',
    noVersion: 'geen versie',
    includeSeamAllowance: 'Dit patroon bevat naadtoeslag',
    theWhiteInsideOfThisBoxShouldMeasure: 'De witte binnenkant van dit vak moet meten',
    theBlackOutsideOfThisBoxShouldMeasure: 'De zwarte buitenkant van dit vak moet meten',
    supportFreeSewingBecomeAPatron: 'Steun FreeSewing. Word donateur',
  },
}

function languageOf(locale) {
  return catalogs[locale] ? locale : 'en'
}

function humanizeKey(key) {
  const spaced = String(key).replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/[_-]+/g, ' ')
  if (!spaced) return String(key)
  return spaced.charAt(0).toUpperCase() + spaced.slice(1)
}

/** A part id such as "front" or "armBinding", in the locale, with English fallback. */
function partPhrase(locale, name) {
  const tail = String(name).split('.').pop() || ''
  if (!tail || /\s/.test(tail)) return ''
  const lower = tail.toLowerCase()
  const token = PART_TOKENS.find((item) => lower === item || lower.endsWith(item))
  if (!token) return ''
  return translate(languageOf(locale), `parts.${token}`)
}

const MARKS = {
  en: { foldHere: 'Fold here' },
  de: { foldHere: 'Hier falten' },
  fr: { foldHere: 'Plier ici' },
  es: { foldHere: 'Doblar aquí' },
  'pt-BR': { foldHere: 'Dobrar aqui' },
  ja: { foldHere: 'ここで折る' },
  it: { foldHere: 'Piegare qui' },
  nl: { foldHere: 'Hier vouwen' },
}

const DESIGN_PHRASES = {}
for (const design of Object.values(freesewingDesigns)) {
  for (const group of [design?.p, design?.s, design?.o]) {
    if (!group) continue
    for (const [key, value] of Object.entries(group)) {
      const phrase = typeof value === 'string' ? value : value?.t
      if (typeof phrase === 'string' && phrase && !DESIGN_PHRASES[key]) DESIGN_PHRASES[key] = phrase
    }
  }
}

/** A sewing mark such as "foldHere", in the locale, with English fallback. */
export function markLabel(locale, key) {
  return barePhrase(locale, key) || key
}

function barePhrase(locale, token) {
  const language = languageOf(locale)
  if (MARKS[language]?.[token]) return MARKS[language][token]
  if (ANNOTATIONS[language]?.[token]) return ANNOTATIONS[language][token]
  if (token === 'grainline' || token === 'cutOnFold' || token === 'cutOnFoldAndGrainline') {
    return annotationPhrase(locale, token)
  }
  return MARKS.en[token] || DESIGN_PHRASES[token] || ''
}

function replaceBareKeys(locale, text) {
  return text.replace(/\b[a-z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*\b/g, (token) => barePhrase(locale, token) || token)
}

function annotationPhrase(locale, key) {
  const language = languageOf(locale)
  if (key === 'grainline') return translate(language, 'ui.grainline')
  if (key === 'cutOnFold') return translate(language, 'ui.cutOnFold')
  if (key === 'cutOnFoldAndGrainline') {
    return `${translate(language, 'ui.cutOnFold')}, ${translate(language, 'ui.grainline')}`
  }
  return ANNOTATIONS[language]?.[key] || ANNOTATIONS.en[key] || humanizeKey(key)
}

function designPhrase(namespace, key) {
  const design = freesewingDesigns[namespace]
  if (!design) return ''
  const part = design.p?.[key]
  if (typeof part === 'string' && part) return part
  const entry = design.s?.[key]
  if (typeof entry === 'string' && entry) return entry
  if (entry && typeof entry.t === 'string') return entry.t
  return ''
}

function phraseFor(locale, namespace, key) {
  if (namespace === 'plugin-annotations') return annotationPhrase(locale, key)
  const part = partPhrase(locale, key)
  if (part) return part
  return designPhrase(namespace, key) || humanizeKey(key)
}

/**
 * FreeSewing text, including namespaced keys such as plugin-annotations:cut.
 * Part names use our glossary. Anything still missing falls back to English.
 */
export function translatePhrase(locale, text) {
  if (typeof text !== 'string') return text
  if (!text.includes(':')) {
    const trimmed = text.trim()
    if (trimmed && !trimmed.includes(' ')) {
      const part = partPhrase(locale, trimmed)
      if (part) return text.replace(trimmed, part)
    }
    for (const token of PART_TOKENS) {
      if (text === catalogs.en.parts[token]) return translate(languageOf(locale), `parts.${token}`)
    }
    return replaceBareKeys(locale, text)
  }
  return replaceBareKeys(
    locale,
    text.replace(/(^|[\s])([A-Za-z][A-Za-z0-9-]*)[:]([A-Za-z0-9_.-]+)/g, (match, lead, namespace, key) => {
      return lead + phraseFor(locale, namespace, key)
    })
  )
}
