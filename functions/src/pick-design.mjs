import { clampOptions } from './clamp.mjs'
import { DESIGN_NAMES, DESIGNS } from './designs.mjs'
import { createGeminiClient, FLASH_LITE_MODEL, FLASH_MODEL } from './gemini.mjs'
import { detectLanguage } from './language.mjs'
import { translate } from './labels.mjs'
import { buildPickPrompt, responseSchema } from './prompt.mjs'
import { assertInstallId, assertPatternAllowed, QuotaError } from './quota.mjs'
import { normalizeLocale } from './units.mjs'

const CLOSEST_BELOW = 0.6
const MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])
const MAX_PHOTO_BYTES = 4 * 1024 * 1024

export class PickInputError extends Error {
  constructor(message) {
    super(message)
    this.name = 'PickInputError'
  }
}

export class PickFailedError extends Error {
  constructor(message) {
    super(message)
    this.name = 'PickFailedError'
  }
}

export { QuotaError }

function normalizePhoto(photo) {
  if (!photo || typeof photo !== 'object') throw new PickInputError('photo is required')
  let mimeType = String(photo.mimeType || '').toLowerCase()
  let data = String(photo.data || '')
  const dataUrl = /^data:(image\/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=\s]+)$/i.exec(data)
  if (dataUrl) {
    mimeType = dataUrl[1].toLowerCase()
    data = dataUrl[2]
  }
  if (!MIME_TYPES.has(mimeType)) throw new PickInputError('photo must be jpeg, png, or webp')
  const compact = data.replace(/\s/g, '')
  if (!/^[A-Za-z0-9+/=]+$/.test(compact)) throw new PickInputError('photo data must be base64')
  const bytes = Math.floor((compact.length * 3) / 4)
  if (bytes < 32 || bytes > MAX_PHOTO_BYTES) throw new PickInputError('photo must be between 32 bytes and 4 MB')
  return { mimeType, data: compact }
}

function coerceOption(value) {
  if (typeof value === 'number' || typeof value === 'boolean') return value
  const text = String(value ?? '').trim()
  if (text === 'true') return true
  if (text === 'false') return false
  const numeric = Number(text)
  if (text !== '' && Number.isFinite(numeric)) return numeric
  return text
}

function optionObject(options) {
  const output = {}
  const entries = Array.isArray(options)
    ? options.map((entry) => [entry?.key, entry?.value])
    : Object.entries(options || {})
  for (const [key, value] of entries) {
    if (!key) continue
    output[String(key)] = coerceOption(value)
  }
  return output
}

function parsePick(text) {
  const raw = String(text || '').trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim()
  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch {
    throw new PickFailedError('Gemini returned invalid JSON')
  }
  if (!parsed || typeof parsed !== 'object') throw new PickFailedError('Gemini returned invalid JSON')
  return parsed
}

function acceptable(parsed) {
  if (parsed.unsupported === 'shorts' || parsed.unsupported === 'polo') return true
  return DESIGN_NAMES.includes(parsed.design)
}

function catalogFor(locale) {
  return DESIGN_NAMES.map((id) => ({ id, name: translate(locale, `designs.${id}`) }))
}

function emptyTokens() {
  return { prompt: 0, output: 0, total: 0 }
}

async function askModel(client, prompt, schema, photo) {
  const errors = []
  for (const model of [FLASH_MODEL, FLASH_LITE_MODEL]) {
    try {
      const result = await client.generate({ model, prompt, schema, photo })
      const parsed = parsePick(result.text)
      if (!acceptable(parsed)) throw new PickFailedError(`Gemini returned an unknown design for ${model}`)
      return { parsed, model, tokens: result.tokens || emptyTokens() }
    } catch (error) {
      errors.push(error?.message || `${model} failed`)
    }
  }
  throw new PickFailedError(errors.join(' | ') || 'pickDesign failed')
}

/**
 * Match a garment photo to a FreeSewing design.
 * The photo is sent to Gemini and then discarded. It is not written to Firestore or the log.
 */
export async function pickDesign(input, runtime = {}) {
  const started = Date.now()
  const locale = normalizeLocale(input?.locale)
  if (!runtime.appCheck) throw new PickInputError('App Check is required')
  const installId = assertInstallId(input?.installId, PickInputError)
  const photo = normalizePhoto(input?.photo)
  const store = runtime.store
  if (!store) throw new PickInputError('quota store is required')
  try {
    await assertPatternAllowed(store, installId)
  } catch (error) {
    if (error instanceof QuotaError) throw new QuotaError(translate(locale, 'ui.rateLimited'))
    throw error
  }

  const client = runtime.client || createGeminiClient({ apiKey: runtime.apiKey || process.env.GEMINI_API_KEY })
  const prompt = buildPickPrompt(locale)
  const schema = responseSchema()
  const answer = await askModel(client, prompt, schema, photo)
  const { parsed, model, tokens } = answer
  const confidence = Math.min(1, Math.max(0, Number(parsed.confidence) || 0))
  const unsupported = parsed.unsupported === 'shorts' || parsed.unsupported === 'polo' ? parsed.unsupported : null
  const explanation = String(parsed.explanation || '').trim().slice(0, 400)
  const closest = !unsupported && confidence < CLOSEST_BELOW
  const manualPicker = Boolean(unsupported || closest)
  let design = null
  let options = {}
  if (!unsupported && DESIGN_NAMES.includes(parsed.design)) {
    design = parsed.design
    options = clampOptions(DESIGNS[design], optionObject(parsed.options))
  }
  const latency_ms = Date.now() - started
  const result = {
    design,
    designName: design ? translate(locale, `designs.${design}`) : null,
    options,
    confidence,
    closest,
    manualPicker,
    unsupported,
    message: unsupported
      ? translate(locale, unsupported === 'shorts' ? 'ui.unsupportedShorts' : 'ui.unsupportedPolo')
      : closest
        ? translate(locale, 'ui.closestDesign')
        : '',
    explanation,
    explanationLocale: detectLanguage(explanation),
    locale,
    model,
    latency_ms,
    tokens,
    catalog: manualPicker ? catalogFor(locale) : [],
  }
  runtime.log?.({
    event: 'pick_design',
    latency_ms,
    design,
    locale,
    model,
    confidence,
    prompt_tokens: tokens.prompt,
    output_tokens: tokens.output,
    total_tokens: tokens.total,
  })
  return result
}
