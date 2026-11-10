import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DESIGN_NAMES } from '../src/designs.mjs'
import { createGeminiClient, FLASH_LITE_MODEL, FLASH_MODEL } from '../src/gemini.mjs'
import { detectLanguage } from '../src/language.mjs'
import { translate } from '../src/labels.mjs'
import { PickInputError, pickDesign } from '../src/pick-design.mjs'
import { DESIGN_GUIDE, responseSchema } from '../src/prompt.mjs'
import { memoryQuotaStore, QuotaError } from '../src/quota.mjs'
import { PatternInputError } from '../src/draft-pattern.mjs'
import { runDraft } from '../src/run-draft.mjs'
import { scoreCases } from '../src/score.mjs'
import { LOCALES } from '../src/units.mjs'

const PHOTO = {
  mimeType: 'image/png',
  data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
}

const INSTALL = 'install-0001'

const measurements = {
  chest: 96,
  waist: 82,
  hips: 98,
  neck: 38,
  shoulderSlope: 13,
  hpsToWaistBack: 45,
}

function clientReturning(payload, { failModels = [] } = {}) {
  const calls = []
  return {
    calls,
    async generate(request) {
      calls.push(request)
      if (failModels.includes(request.model)) throw new Error(`down ${request.model}`)
      const body = typeof payload === 'function' ? payload(request) : payload
      return {
        text: JSON.stringify(body),
        tokens: { prompt: 11, output: 5, total: 16 },
      }
    },
  }
}

function runtime(client, extras = {}) {
  return {
    appCheck: true,
    store: memoryQuotaStore(),
    client,
    ...extras,
  }
}

describe('pickDesign', () => {
  test('the prompt lists every design and the schema requires a design id', async () => {
    const client = clientReturning({
      design: 'teagan',
      unsupported: 'none',
      confidence: 0.91,
      options: [],
      explanation: 'Das ist ein schlichtes Shirt mit kurzen Ärmeln.',
    })
    await pickDesign(
      { photo: PHOTO, locale: 'de', installId: INSTALL },
      runtime(client)
    )
    const request = client.calls[0]
    expect(request.model).toBe(FLASH_MODEL)
    expect(request.prompt).toContain('German')
    expect(request.prompt).toContain('unsupported')
    for (const name of DESIGN_NAMES) expect(request.prompt).toContain(name)
    expect(request.schema).toEqual(responseSchema())
    expect(request.schema.properties.design.enum).toEqual([...DESIGN_NAMES, 'unsupported'])
    expect(request.schema.required).toEqual(['design', 'unsupported', 'confidence', 'options', 'explanation'])
    expect(DESIGN_GUIDE.map(([id]) => id).sort()).toEqual([...DESIGN_NAMES].sort())
    expect(request.photo).toEqual(PHOTO)
  })

  test('options are clamped and unknown keys are dropped', async () => {
    const client = clientReturning({
      design: 'brian',
      unsupported: 'none',
      confidence: 0.88,
      options: [
        { key: 'chestEase', value: '80' },
        { key: 'notARealOption', value: '1' },
      ],
      explanation: 'A plain block.',
      designTitle: 'Ignore this title',
    })
    const result = await pickDesign(
      { photo: PHOTO, locale: 'de', installId: INSTALL },
      runtime(client)
    )
    expect(result.options.chestEase).toBeCloseTo(0.35, 5)
    expect(result.options.notARealOption).toBeUndefined()
    expect(result.designName).toBe(translate('de', 'designs.brian'))
    expect(result.designName).not.toBe('Ignore this title')
    expect(result.closest).toBe(false)
    expect(result.manualPicker).toBe(false)
    expect(result.catalog).toEqual([])
  })

  test('Flash-Lite is used when Flash fails', async () => {
    const client = clientReturning(
      {
        design: 'hugo',
        unsupported: 'none',
        confidence: 0.8,
        options: [],
        explanation: 'A hooded sweatshirt.',
      },
      { failModels: [FLASH_MODEL] }
    )
    const result = await pickDesign(
      { photo: PHOTO, locale: 'en', installId: INSTALL },
      runtime(client)
    )
    expect(client.calls.map((call) => call.model)).toEqual([FLASH_MODEL, FLASH_LITE_MODEL])
    expect(result.model).toBe(FLASH_LITE_MODEL)
    expect(result.design).toBe('hugo')
  })

  test('a used free pattern is refused and the photo is not stored', async () => {
    const store = memoryQuotaStore()
    await store.reserve(INSTALL)
    const logs = []
    const client = clientReturning({
      design: 'teagan',
      unsupported: 'none',
      confidence: 0.9,
      options: [],
      explanation: 'nope',
    })
    await expect(
      pickDesign(
        { photo: PHOTO, locale: 'de', installId: INSTALL },
        runtime(client, { store, log: (entry) => logs.push(entry) })
      )
    ).rejects.toThrow(QuotaError)
    expect(client.calls).toHaveLength(0)
    expect(JSON.stringify(store.snapshot())).not.toContain(PHOTO.data)
    expect(logs).toHaveLength(0)
  })

  test('App Check and a photo are required', async () => {
    const client = clientReturning({ design: 'teagan', unsupported: 'none', confidence: 1, options: [], explanation: 'x' })
    await expect(
      pickDesign({ photo: PHOTO, locale: 'en', installId: INSTALL }, runtime(client, { appCheck: false }))
    ).rejects.toThrow(PickInputError)
    await expect(
      pickDesign({ photo: { mimeType: 'image/gif', data: PHOTO.data }, locale: 'en', installId: INSTALL }, runtime(client))
    ).rejects.toThrow('photo must be jpeg, png, or webp')
  })

  test('confidence below 0.6 returns the closest design and the manual picker', async () => {
    const client = clientReturning({
      design: 'teagan',
      unsupported: 'none',
      confidence: 0.59,
      options: [],
      explanation: 'Das ist ein schlichtes Shirt mit kurzen Ärmeln.',
    })
    const result = await pickDesign(
      { photo: PHOTO, locale: 'de', installId: INSTALL },
      runtime(client)
    )
    expect(result.closest).toBe(true)
    expect(result.manualPicker).toBe(true)
    expect(result.design).toBe('teagan')
    expect(result.message).toBe(translate('de', 'ui.closestDesign'))
    expect(result.catalog).toHaveLength(DESIGN_NAMES.length)
    expect(result.catalog[0].name).not.toContain('{{missing:')
  })

  test('confidence of 0.6 is a direct match', async () => {
    const client = clientReturning({
      design: 'teagan',
      unsupported: 'none',
      confidence: 0.6,
      options: [],
      explanation: 'A knit shirt.',
    })
    const result = await pickDesign(
      { photo: PHOTO, locale: 'en', installId: INSTALL },
      runtime(client)
    )
    expect(result.closest).toBe(false)
    expect(result.manualPicker).toBe(false)
  })

  test('shorts and polo are unsupported in all eight languages', async () => {
    for (const locale of LOCALES) {
      for (const unsupported of ['shorts', 'polo']) {
        const client = clientReturning({
          design: 'teagan',
          unsupported,
          confidence: 0.95,
          options: [{ key: 'chestEase', value: '10' }],
          explanation: 'not used as the design name',
        })
        const result = await pickDesign(
          { photo: PHOTO, locale, installId: INSTALL },
          runtime(client)
        )
        expect(result.design).toBeNull()
        expect(result.options).toEqual({})
        expect(result.unsupported).toBe(unsupported)
        expect(result.manualPicker).toBe(true)
        const key = unsupported === 'shorts' ? 'ui.unsupportedShorts' : 'ui.unsupportedPolo'
        expect(result.message).toBe(translate(locale, key))
        expect(result.message).not.toContain('{{missing:')
      }
    }
  })

  test('German and Japanese explanations stay in the requested language', async () => {
    const german = 'Das ist ein schlichtes Shirt mit kurzen Ärmeln und einem runden Ausschnitt.'
    const japanese = 'これは半袖のTシャツです。襟やボタンはありません。'
    const germanClient = clientReturning({
      design: 'teagan',
      unsupported: 'none',
      confidence: 0.9,
      options: [],
      explanation: german,
    })
    const germanResult = await pickDesign(
      { photo: PHOTO, locale: 'de', installId: INSTALL },
      runtime(germanClient)
    )
    expect(germanClient.calls[0].prompt).toContain('Write the explanation in German.')
    expect(germanResult.explanation).toBe(german)
    expect(detectLanguage(germanResult.explanation)).toBe('de')
    expect(germanResult.explanationLocale).toBe('de')

    const japaneseClient = clientReturning({
      design: 'teagan',
      unsupported: 'none',
      confidence: 0.9,
      options: [],
      explanation: japanese,
    })
    const japaneseResult = await pickDesign(
      { photo: PHOTO, locale: 'ja', installId: INSTALL },
      runtime(japaneseClient)
    )
    expect(japaneseClient.calls[0].prompt).toContain('Write the explanation in Japanese.')
    expect(japaneseResult.explanation).toBe(japanese)
    expect(detectLanguage(japaneseResult.explanation)).toBe('ja')
    expect(japaneseResult.explanationLocale).toBe('ja')
  })

  test('the log records tokens and latency and omits the photo', async () => {
    const logs = []
    const client = clientReturning({
      design: 'florent',
      unsupported: 'none',
      confidence: 0.77,
      options: [],
      explanation: 'A flat cap.',
    })
    const result = await pickDesign(
      { photo: PHOTO, locale: 'fr', installId: INSTALL },
      runtime(client, { log: (entry) => logs.push(entry) })
    )
    expect(logs).toEqual([
      {
        event: 'pick_design',
        latency_ms: result.latency_ms,
        design: 'florent',
        locale: 'fr',
        model: FLASH_MODEL,
        confidence: 0.77,
        prompt_tokens: 11,
        output_tokens: 5,
        total_tokens: 16,
      },
    ])
    expect(JSON.stringify(logs)).not.toContain(PHOTO.data)
    expect(result.tokens).toEqual({ prompt: 11, output: 5, total: 16 })
  })

  test('the Gemini request is JSON schema with the photo and no stored key in the error', async () => {
    let body
    const client = createGeminiClient({
      apiKey: 'test-key',
      fetchImpl: async (url, options) => {
        expect(url).toContain(`/models/${FLASH_MODEL}:generateContent`)
        body = JSON.parse(options.body)
        return { ok: false, status: 503, json: async () => ({}) }
      },
    })
    await expect(
      client.generate({
        model: FLASH_MODEL,
        prompt: 'match',
        schema: responseSchema(),
        photo: PHOTO,
      })
    ).rejects.toThrow(`Gemini ${FLASH_MODEL} failed with status 503`)
    expect(body.generationConfig.responseMimeType).toBe('application/json')
    expect(body.generationConfig.responseSchema.required).toContain('design')
    expect(body.contents[0].parts[1].inline_data).toEqual({ mime_type: 'image/png', data: PHOTO.data })
    expect(body.contents[0].parts[0].text).toBe('match')
  })
})

describe('pattern quota', () => {
  test('the first draft is kept and a second draft is refused', async () => {
    const store = memoryQuotaStore()
    const logs = []
    const input = {
      design: 'brian',
      measurements,
      units: 'metric',
      locale: 'en',
      paper: 'a4',
      installId: INSTALL,
    }
    const first = await runDraft(input, { appCheck: true, store, pdf: false, log: (entry) => logs.push(entry) })
    expect(first.design).toBe('brian')
    expect(first.latency_ms).toEqual(expect.any(Number))
    expect(logs[0]).toMatchObject({ event: 'pattern_drafted', design: 'brian', locale: 'en' })
    expect(store.snapshot()[INSTALL]).toBe(1)
    await expect(runDraft(input, { appCheck: true, store, pdf: false })).rejects.toThrow(QuotaError)
    expect(store.snapshot()[INSTALL]).toBe(1)
  })

  test('a failed draft does not use the free pattern', async () => {
    const store = memoryQuotaStore()
    await expect(
      runDraft(
        { design: 'not-a-design', measurements, units: 'metric', locale: 'en', installId: INSTALL },
        { appCheck: true, store, pdf: false }
      )
    ).rejects.toThrow(PatternInputError)
    expect(store.snapshot()[INSTALL]).toBe(0)
  })
})

describe('photo regression score', () => {
  function cases() {
    return DESIGN_NAMES.map((design) => ({ id: design, design, photo: PHOTO }))
  }

  function scoredClient(correctCount) {
    let index = 0
    return {
      async generate() {
        const item = cases()[index]
        const design = index < correctCount ? item.design : item.design === 'aaron' ? 'brian' : 'aaron'
        index += 1
        return {
          text: JSON.stringify({
            design,
            unsupported: 'none',
            confidence: 0.9,
            options: [],
            explanation: 'ok',
          }),
          tokens: { prompt: 1, output: 1, total: 2 },
        }
      },
    }
  }

  test('the photo set has one real image for every design', () => {
    const manifest = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), '../regression/manifest.json'), 'utf8'))
    expect(manifest.map((item) => item.design).sort()).toEqual([...DESIGN_NAMES].sort())
    for (const item of manifest) {
      const bytes = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '../regression/photos', item.file))
      const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8
      const png = bytes[0] === 0x89 && bytes[1] === 0x50
      expect(jpeg || png).toBe(true)
      expect(bytes.length).toBeGreaterThan(1000)
    }
  })

  test('16 of 20 passes and 15 of 20 fails', async () => {
    const passing = await scoreCases(cases(), scoredClient(16))
    expect(passing.correct).toBe(16)
    expect(passing.total).toBe(20)
    expect(passing.passed).toBe(true)
    const failing = await scoreCases(cases(), scoredClient(15))
    expect(failing.correct).toBe(15)
    expect(failing.passed).toBe(false)
  })
})
