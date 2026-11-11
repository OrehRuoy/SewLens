import { logger } from 'firebase-functions'
import { onCall, HttpsError } from 'firebase-functions/v2/https'
import { defineSecret } from 'firebase-functions/params'
import { firestorePromoStore, firestoreQuotaStore } from './src/quota-store.mjs'
import { playPurchases } from './src/play.mjs'
import { redeemPromo as redeem, verifyPurchase as verify } from './src/purchases.mjs'

const geminiApiKey = defineSecret('GEMINI_API_KEY')

function logEvent(entry) {
  const safe = {}
  for (const [key, value] of Object.entries(entry || {})) {
    if (key === 'photo' || key === 'image' || key === 'inlineData' || key === 'data') continue
    safe[key] = value
  }
  logger.info(safe.event || 'sewlens', safe)
}

function geminiKey() {
  try {
    const value = geminiApiKey.value()
    if (value) return value
  } catch {
    // The local functions emulator has no Secret Manager binding.
  }
  return process.env.GEMINI_API_KEY || ''
}

function hasAppCheck(request) {
  if (request.app) return true
  return process.env.FUNCTIONS_EMULATOR === 'true'
}

// The callable gateway rejects missing App Check before the handler runs.
// The emulator has no debug token. Production leaves this env var unset.
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== 'true'

function toHttps(error) {
  const message = String(error?.message || 'request failed').replace(/key=[^&\s]+/gi, 'key=redacted')
  logger.warn(message)
  const name = error?.name
  if (name === 'PickInputError' || name === 'PatternInputError' || name === 'PurchaseInputError' || name === 'ReceiptError') {
    return new HttpsError('invalid-argument', error.message)
  }
  if (name === 'QuotaError') return new HttpsError('resource-exhausted', error.message)
  if (name === 'PickFailedError') return new HttpsError('unavailable', 'pickDesign failed')
  return new HttpsError('internal', 'request failed')
}

const lightOptions = {
  region: 'us-central1',
  memory: '256MiB',
  timeoutSeconds: 30,
  invoker: 'public',
  enforceAppCheck,
}

/**
 * draftPattern(design, measurements, options, units, paper, locale, installId)
 * Returns SVG, a tiled Letter/A4 PDF, and yardage. One free pattern per install.
 * FreeSewing stays inside the handler so receipt checks do not cold-start it.
 */
export const draftPattern = onCall(
  {
    region: 'us-central1',
    memory: '1GiB',
    timeoutSeconds: 120,
    invoker: 'public',
    enforceAppCheck,
  },
  async (request) => {
    try {
      const { runDraft } = await import('./src/run-draft.mjs')
      const { firestoreFeedbackStore } = await import('./src/feedback-store.mjs')
      return await runDraft(request.data || {}, {
        appCheck: hasAppCheck(request),
        store: firestoreQuotaStore(),
        feedback: firestoreFeedbackStore(),
        log: logEvent,
      })
    } catch (error) {
      throw toHttps(error)
    }
  }
)

/**
 * pickDesign(photo, locale, installId)
 * Gemini Flash picks a design. Flash-Lite is the fallback. The photo is not stored.
 */
export const pickDesign = onCall(
  {
    region: 'us-central1',
    memory: '512MiB',
    timeoutSeconds: 60,
    invoker: 'public',
    enforceAppCheck,
    secrets: [geminiApiKey],
  },
  async (request) => {
    try {
      const { pickDesign: pick } = await import('./src/pick-design.mjs')
      return await pick(request.data || {}, {
        appCheck: hasAppCheck(request),
        store: firestoreQuotaStore(),
        apiKey: geminiKey(),
        log: logEvent,
      })
    } catch (error) {
      throw toHttps(error)
    }
  }
)

/** verifyPurchase(installId, receipt). Grants a credit or unlimited, or revokes a refund. */
export const verifyPurchase = onCall(lightOptions, async (request) => {
  try {
    return await verify(request.data || {}, {
      appCheck: hasAppCheck(request),
      store: firestoreQuotaStore(),
      play: playPurchases(),
      log: logEvent,
    })
  } catch (error) {
    throw toHttps(error)
  }
})

/** redeemPromo(installId, code, locale). A creator code grants unlimited once. */
export const redeemPromo = onCall(lightOptions, async (request) => {
  try {
    return await redeem(request.data || {}, {
      appCheck: hasAppCheck(request),
      store: firestoreQuotaStore(),
      promos: firestorePromoStore(),
      log: logEvent,
    })
  } catch (error) {
    throw toHttps(error)
  }
})
