import { getApps, initializeApp } from 'firebase-admin/app'
import { getFirestore, FieldValue } from 'firebase-admin/firestore'
import { FREE_PATTERN_CAP, QuotaError } from './quota.mjs'
import { CREDIT_PRODUCT, UNLIMITED_PRODUCT, productKind } from './products.mjs'

function database() {
  if (!getApps().length) initializeApp()
  return getFirestore()
}

function refFor(installId) {
  return database().doc(`installs/${installId}`)
}

function entitlementOf(data) {
  return {
    patternCount: Number(data.patternCount) || 0,
    credits: Number(data.credits) || 0,
    unlimited: data.unlimited === true,
  }
}

function transactionsOf(data) {
  return { ...(data.transactions || {}) }
}

/** Firestore counter plus credits and the unlimited flag. Never stores a receipt or a photo. */
export function firestoreQuotaStore() {
  return {
    async count(installId) {
      const snap = await refFor(installId).get()
      if (!snap.exists) return 0
      return Number(snap.data().patternCount) || 0
    },
    async entitlement(installId) {
      const snap = await refFor(installId).get()
      return entitlementOf(snap.exists ? snap.data() : {})
    },
    async grant(installId, { transactionId, productId }) {
      const kind = productKind(productId)
      if (!kind || !transactionId) throw new QuotaError('unknown product')
      const ref = refFor(installId)
      return database().runTransaction(async (tx) => {
        const snap = await tx.get(ref)
        const data = snap.exists ? snap.data() : {}
        const transactions = transactionsOf(data)
        if (transactions[transactionId]) return entitlementOf(data)
        transactions[transactionId] = { productId, consumed: false, revoked: false }
        const next = { transactions }
        if (kind === 'credit') next.credits = (Number(data.credits) || 0) + 1
        if (kind === 'unlimited') next.unlimited = true
        tx.set(ref, next, { merge: true })
        return entitlementOf({ ...data, ...next })
      })
    },
    async revoke(installId, transactionId) {
      const ref = refFor(installId)
      return database().runTransaction(async (tx) => {
        const snap = await tx.get(ref)
        const data = snap.exists ? snap.data() : {}
        const transactions = transactionsOf(data)
        const row = transactions[transactionId]
        if (!row || row.revoked) return entitlementOf(data)
        row.revoked = true
        const next = { transactions }
        if (row.productId === UNLIMITED_PRODUCT) {
          next.unlimited = Object.values(transactions).some((item) => item.productId === UNLIMITED_PRODUCT && !item.revoked)
        } else if (!row.consumed) {
          next.credits = Math.max(0, (Number(data.credits) || 0) - 1)
        }
        tx.set(ref, next, { merge: true })
        return entitlementOf({ ...data, ...next })
      })
    },
    async reserve(installId, design) {
      const ref = refFor(installId)
      await database().runTransaction(async (tx) => {
        const snap = await tx.get(ref)
        const data = snap.exists ? snap.data() : {}
        if (data.unlimited === true) {
          tx.set(ref, { design, lastGrant: 'unlimited' }, { merge: true })
          return
        }
        const count = Number(data.patternCount) || 0
        if (count < FREE_PATTERN_CAP) {
          const next = { patternCount: count + 1, lastGrant: 'free' }
          if (design) next.design = design
          tx.set(ref, next, { merge: true })
          return
        }
        const transactions = transactionsOf(data)
        const openId = Object.keys(transactions).find((id) => {
          const row = transactions[id]
          return row.productId === CREDIT_PRODUCT && !row.consumed && !row.revoked
        })
        if ((Number(data.credits) || 0) > 0 && openId) {
          transactions[openId] = { ...transactions[openId], consumed: true }
          const next = { credits: (Number(data.credits) || 0) - 1, transactions, lastGrant: 'credit' }
          if (design) next.design = design
          tx.set(ref, next, { merge: true })
          return
        }
        throw new QuotaError('free pattern already used')
      })
    },
    async assertAdjustment(installId, design) {
      const snap = await refFor(installId).get()
      const drafted = snap.exists ? String(snap.data().design || '') : ''
      if (!drafted) throw new QuotaError('draft a pattern before adjusting the fit')
      if (drafted !== design) throw new QuotaError('free pattern already used')
    },
    async release(installId) {
      const ref = refFor(installId)
      await database().runTransaction(async (tx) => {
        const snap = await tx.get(ref)
        if (!snap.exists) return
        const data = snap.data()
        if (data.lastGrant === 'credit') {
          const transactions = transactionsOf(data)
          const spentId = Object.keys(transactions).reverse().find((id) => {
            const row = transactions[id]
            return row.productId === CREDIT_PRODUCT && row.consumed && !row.revoked
          })
          if (spentId) transactions[spentId] = { ...transactions[spentId], consumed: false }
          tx.set(ref, {
            credits: (Number(data.credits) || 0) + 1,
            transactions,
            lastGrant: FieldValue.delete(),
          }, { merge: true })
          return
        }
        if (data.lastGrant === 'free') {
          tx.set(ref, {
            patternCount: Math.max(0, (Number(data.patternCount) || 0) - 1),
            lastGrant: FieldValue.delete(),
          }, { merge: true })
        }
      })
    },
  }
}

export function firestorePromoStore() {
  return {
    async claim(code) {
      const ref = database().doc(`promoCodes/${code}`)
      return database().runTransaction(async (tx) => {
        const snap = await tx.get(ref)
        const remaining = snap.exists ? Number(snap.data().remaining) || 0 : 0
        if (remaining < 1) return false
        tx.set(ref, { remaining: remaining - 1 }, { merge: true })
        return true
      })
    },
  }
}
