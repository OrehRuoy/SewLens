import { playPurchases } from '../src/play.mjs'
import { CREDIT_PRODUCT, UNLIMITED_PRODUCT } from '../src/products.mjs'
import { memoryPromoStore, redeemPromo, verifyPurchase } from '../src/purchases.mjs'
import { memoryQuotaStore, QuotaError } from '../src/quota.mjs'
import { ReceiptError, signFixture, verifyReceipt } from '../src/receipts.mjs'

const INSTALL = 'install-purchases'
const SECRET = 'fixture-secret'

function runtime(store, extra = {}) {
  return { appCheck: true, store, fixtureSecret: SECRET, log: () => {}, ...extra }
}

function signed(body) {
  return { signed: signFixture(body, SECRET) }
}

describe('receipt verification', () => {
  test('a signed fixture grants one credit and a second copy does not', async () => {
    const store = memoryQuotaStore()
    const receipt = signed({ productId: CREDIT_PRODUCT, transactionId: 'tx-credit' })
    const first = await verifyPurchase({ installId: INSTALL, receipt }, runtime(store))
    const second = await verifyPurchase({ installId: INSTALL, receipt }, runtime(store))
    expect(first).toEqual({ patternCount: 0, credits: 1, unlimited: false })
    expect(second).toEqual(first)
    expect(store.snapshot()[INSTALL]).toBeUndefined()
  })

  test('production rejects an unsigned fixture and a receipt that does not chain to Apple', async () => {
    await expect(verifyReceipt({ fixture: true })).rejects.toBeInstanceOf(ReceiptError)
    await expect(verifyReceipt({ signed: signFixture({ productId: CREDIT_PRODUCT, transactionId: 'tx' }, SECRET) })).rejects.toBeInstanceOf(ReceiptError)
    await expect(verifyReceipt({
      platform: 'ios',
      signedTransaction: `eyJhbGciOiJFUzI1NiJ9.${Buffer.from('{}').toString('base64url')}.aaaa`,
    })).rejects.toBeInstanceOf(ReceiptError)
  })

  test('Play grants unlimited only when a purchase lookup is configured', async () => {
    const store = memoryQuotaStore()
    const receipt = { platform: 'android', productId: UNLIMITED_PRODUCT, purchaseToken: 'token-1' }
    await expect(verifyPurchase({ installId: INSTALL, receipt }, runtime(store))).rejects.toBeInstanceOf(ReceiptError)
    const granted = await verifyPurchase({ installId: INSTALL, receipt }, runtime(store, {
      play: { async get(productId, token) {
        expect(productId).toBe(UNLIMITED_PRODUCT)
        expect(token).toBe('token-1')
        return { purchaseState: 0, orderId: 'GPA.1' }
      } },
    }))
    expect(granted.unlimited).toBe(true)
  })

  test('the Play client reads a purchased order and rejects anything else', async () => {
    const calls = []
    const fetchImpl = async (url, options) => {
      calls.push(String(url))
      expect(options.headers.Authorization || options.headers['Metadata-Flavor']).toBeTruthy()
      if (String(url).includes('metadata.google.internal')) {
        return { ok: true, json: async () => ({ access_token: 'ya29.test' }) }
      }
      return { ok: true, json: async () => ({ purchaseState: 0, orderId: 'GPA.1', consumptionState: 0 }) }
    }
    const play = playPurchases({ fetchImpl, packageName: 'com.sewlens.app' })
    const purchase = await play.get(CREDIT_PRODUCT, 'token-1')
    expect(purchase).toEqual({ purchaseState: 0, orderId: 'GPA.1', revoked: false })
    expect(calls[1]).toContain('/applications/com.sewlens.app/purchases/products/')
    expect(calls[1]).toContain(encodeURIComponent('token-1'))
    const canceled = playPurchases({
      fetchImpl: async (url) => {
        if (String(url).includes('metadata.google.internal')) {
          return { ok: true, json: async () => ({ access_token: 'ya29.test' }) }
        }
        return { ok: true, json: async () => ({ purchaseState: 1, orderId: 'GPA.2' }) }
      },
    })
    await expect(canceled.get(CREDIT_PRODUCT, 'token-2')).rejects.toBeInstanceOf(ReceiptError)
  })
})

describe('entitlement rules', () => {
  test('the free pattern is spent before a credit, and a failed credit draft is refunded', async () => {
    const store = memoryQuotaStore()
    await store.reserve(INSTALL, 'brian')
    await expect(store.reserve(INSTALL, 'aaron')).rejects.toBeInstanceOf(QuotaError)
    expect(store.snapshot()[INSTALL]).toBe(1)
    await store.grant(INSTALL, { transactionId: 'tx-1', productId: CREDIT_PRODUCT })
    await store.grant(INSTALL, { transactionId: 'tx-extra', productId: CREDIT_PRODUCT })
    await store.revoke(INSTALL, 'tx-extra')
    expect((await store.entitlement(INSTALL)).credits).toBe(1)
    await store.reserve(INSTALL, 'aaron')
    expect((await store.entitlement(INSTALL)).credits).toBe(0)
    expect(store.snapshot()[INSTALL]).toBe(1)
    await store.release(INSTALL)
    expect((await store.entitlement(INSTALL)).credits).toBe(1)
    await store.reserve(INSTALL, 'aaron')
    await store.revoke(INSTALL, 'tx-1')
    expect((await store.entitlement(INSTALL)).credits).toBe(0)
    expect(store.snapshot()[INSTALL]).toBe(1)
  })

  test('unlimited does not use the free pattern, a refund removes it, and fit adjustment still works', async () => {
    const store = memoryQuotaStore()
    await store.reserve(INSTALL, 'brian')
    await store.grant(INSTALL, { transactionId: 'life', productId: UNLIMITED_PRODUCT })
    await store.reserve(INSTALL, 'aaron')
    expect(store.snapshot()[INSTALL]).toBe(1)
    await store.assertAdjustment(INSTALL, 'aaron')
    await expect(store.assertAdjustment(INSTALL, 'hugo')).rejects.toBeInstanceOf(QuotaError)
    const revoked = await verifyPurchase({
      installId: INSTALL,
      receipt: signed({ productId: UNLIMITED_PRODUCT, transactionId: 'life', revoked: true }),
    }, runtime(store))
    expect(revoked.unlimited).toBe(false)
    await expect(store.reserve(INSTALL, 'simon')).rejects.toBeInstanceOf(QuotaError)
  })

  test('a creator code unlocks once and an unknown code does not', async () => {
    const store = memoryQuotaStore()
    const promos = memoryPromoStore({ CREATOR: 1 })
    const options = { appCheck: true, store, promos, log: () => {} }
    const first = await redeemPromo({ installId: INSTALL, code: 'creator' }, options)
    expect(first.unlimited).toBe(true)
    const second = await redeemPromo({ installId: INSTALL, code: 'creator' }, options)
    expect(second.unlimited).toBe(true)
    await expect(redeemPromo({ installId: 'install-other', code: 'CREATOR' }, options)).rejects.toThrow('unknown code')
    expect(JSON.stringify(store.snapshot())).not.toMatch(/photo|receipt|secret/i)
  })
})
