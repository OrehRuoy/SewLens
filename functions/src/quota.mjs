/** One free drafted pattern per install, then a credit or an unlimited unlock. Photos are never written. */

import { CREDIT_PRODUCT, UNLIMITED_PRODUCT, productKind } from './products.mjs'

export const FREE_PATTERN_CAP = 1

export class QuotaError extends Error {
  constructor(message) {
    super(message)
    this.name = 'QuotaError'
  }
}

export function assertInstallId(value, errorClass) {
  const id = String(value || '').trim()
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(id)) {
    throw new errorClass('installId is required')
  }
  return id
}

function blankAccount() {
  return { credits: 0, unlimited: false, transactions: new Map(), source: '' }
}

export function memoryQuotaStore() {
  const counts = new Map()
  const designs = new Map()
  const accounts = new Map()
  const account = (installId) => {
    if (!accounts.has(installId)) accounts.set(installId, blankAccount())
    return accounts.get(installId)
  }
  const entitlementOf = (installId) => ({
    patternCount: counts.get(installId) || 0,
    credits: account(installId).credits,
    unlimited: account(installId).unlimited,
  })
  return {
    async count(installId) {
      return counts.get(installId) || 0
    },
    async entitlement(installId) {
      return entitlementOf(installId)
    },
    async grant(installId, { transactionId, productId }) {
      const kind = productKind(productId)
      if (!kind || !transactionId) throw new QuotaError('unknown product')
      const row = account(installId)
      if (row.transactions.has(transactionId)) return entitlementOf(installId)
      row.transactions.set(transactionId, { productId, consumed: false, revoked: false })
      if (kind === 'credit') row.credits += 1
      else row.unlimited = true
      return entitlementOf(installId)
    },
    async revoke(installId, transactionId) {
      const row = account(installId)
      const tx = row.transactions.get(transactionId)
      if (!tx || tx.revoked) return entitlementOf(installId)
      tx.revoked = true
      if (tx.productId === UNLIMITED_PRODUCT) {
        row.unlimited = [...row.transactions.values()].some((item) => item.productId === UNLIMITED_PRODUCT && !item.revoked)
      } else if (!tx.consumed) {
        row.credits = Math.max(0, row.credits - 1)
      }
      return entitlementOf(installId)
    },
    async reserve(installId, design) {
      const row = account(installId)
      if (row.unlimited) {
        if (design) designs.set(installId, design)
        row.source = 'unlimited'
        return
      }
      const count = counts.get(installId) || 0
      if (count < FREE_PATTERN_CAP) {
        counts.set(installId, count + 1)
        if (design) designs.set(installId, design)
        row.source = 'free'
        return
      }
      const open = [...row.transactions.values()].find((item) => item.productId === CREDIT_PRODUCT && !item.consumed && !item.revoked)
      if (row.credits > 0 && open) {
        open.consumed = true
        row.credits -= 1
        if (design) designs.set(installId, design)
        row.source = 'credit'
        return
      }
      throw new QuotaError('free pattern already used')
    },
    async release(installId) {
      const row = account(installId)
      if (row.source === 'free') counts.set(installId, Math.max(0, (counts.get(installId) || 0) - 1))
      if (row.source === 'credit') {
        const spent = [...row.transactions.values()].reverse().find((item) => item.productId === CREDIT_PRODUCT && item.consumed && !item.revoked)
        if (spent) spent.consumed = false
        row.credits += 1
      }
      row.source = ''
    },
    async assertAdjustment(installId, design) {
      const drafted = designs.get(installId)
      if (!drafted) throw new QuotaError('draft a pattern before adjusting the fit')
      if (drafted !== design) throw new QuotaError('free pattern already used')
    },
    snapshot() {
      return Object.fromEntries(counts)
    },
  }
}

export async function assertPatternAllowed(store, installId) {
  const count = await store.count(installId)
  if (count >= FREE_PATTERN_CAP) throw new QuotaError('free pattern already used')
}
