import { assertInstallId, QuotaError } from './quota.mjs'
import { UNLIMITED_PRODUCT } from './products.mjs'
import { verifyReceipt } from './receipts.mjs'

export class PurchaseInputError extends QuotaError {
  constructor(message) {
    super(message)
    this.name = 'PurchaseInputError'
  }
}

function installOf(input) {
  return assertInstallId(input?.installId, PurchaseInputError)
}

export async function verifyPurchase(input, runtime = {}) {
  if (runtime.appCheck === false) throw new PurchaseInputError('App Check is required')
  const installId = installOf(input)
  if (!runtime.store) throw new PurchaseInputError('quota store is required')
  const claim = await verifyReceipt(input?.receipt, runtime)
  const entitlement = claim.revoked
    ? await runtime.store.revoke(installId, claim.transactionId)
    : await runtime.store.grant(installId, claim)
  runtime.log?.({
    event: 'purchase_verified',
    product: claim.productId,
    revoked: claim.revoked,
  })
  return entitlement
}

export function memoryPromoStore(codes = {}) {
  const left = new Map(Object.entries(codes).map(([code, count]) => [code, Number(count) || 0]))
  return {
    async claim(code) {
      const remaining = left.get(code) || 0
      if (remaining < 1) return false
      left.set(code, remaining - 1)
      return true
    },
  }
}

export async function redeemPromo(input, runtime = {}) {
  if (runtime.appCheck === false) throw new PurchaseInputError('App Check is required')
  const installId = installOf(input)
  if (!runtime.store || !runtime.promos) throw new PurchaseInputError('promo store is required')
  const code = String(input?.code || '').trim().toUpperCase()
  if (!/^[A-Z0-9-]{6,32}$/.test(code)) throw new PurchaseInputError('invalid code')
  const current = await runtime.store.entitlement(installId)
  if (current.unlimited) return current
  const claimed = await runtime.promos.claim(code)
  if (!claimed) throw new PurchaseInputError('unknown code')
  const entitlement = await runtime.store.grant(installId, {
    transactionId: `promo:${code}`,
    productId: UNLIMITED_PRODUCT,
  })
  runtime.log?.({ event: 'promo_redeemed' })
  return entitlement
}
