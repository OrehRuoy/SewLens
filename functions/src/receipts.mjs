import { createHmac, timingSafeEqual, verify as verifySignature, X509Certificate } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { BUNDLE_ID, productKind } from './products.mjs'

export class ReceiptError extends Error {
  constructor(message) {
    super(message)
    this.name = 'ReceiptError'
  }
}

const APPLE_ROOT = new X509Certificate(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'certs', 'AppleRootCA-G3.pem'))
)

function b64url(value) {
  return Buffer.from(value).toString('base64url')
}

function fromB64url(value) {
  return Buffer.from(String(value), 'base64url')
}

export function signFixture(body, secret) {
  const payload = b64url(JSON.stringify(body))
  const sig = b64url(createHmac('sha256', secret).update(payload).digest())
  return `fix.${payload}.${sig}`
}

function verifyFixture(signed, secret) {
  const parts = String(signed).split('.')
  if (parts.length !== 3 || parts[0] !== 'fix') throw new ReceiptError('fixture receipt is not valid')
  const expected = b64url(createHmac('sha256', secret).update(parts[1]).digest())
  const left = Buffer.from(expected)
  const right = Buffer.from(parts[2])
  if (left.length !== right.length || !timingSafeEqual(left, right)) {
    throw new ReceiptError('fixture receipt is not valid')
  }
  const body = JSON.parse(fromB64url(parts[1]).toString('utf8'))
  return claimFrom(body)
}

function claimFrom(body) {
  const productId = String(body.productId || '')
  if (!productKind(productId)) throw new ReceiptError('unknown product')
  const transactionId = String(body.transactionId || '').trim()
  if (!transactionId) throw new ReceiptError('transactionId is required')
  return {
    productId,
    transactionId,
    revoked: body.revoked === true || Boolean(body.revocationDate),
  }
}

function pemFromDer(der) {
  const body = Buffer.from(der).toString('base64').replace(/(.{64})/g, '$1\n')
  return `-----BEGIN CERTIFICATE-----\n${body}\n-----END CERTIFICATE-----\n`
}

function verifyApple(signedTransaction) {
  const parts = String(signedTransaction || '').split('.')
  if (parts.length !== 3) throw new ReceiptError('signed transaction is not valid')
  let header
  let payload
  try {
    header = JSON.parse(fromB64url(parts[0]).toString('utf8'))
    payload = JSON.parse(fromB64url(parts[1]).toString('utf8'))
  } catch {
    throw new ReceiptError('signed transaction is not valid')
  }
  const chain = Array.isArray(header.x5c) ? header.x5c.map((part) => new X509Certificate(pemFromDer(Buffer.from(part, 'base64')))) : []
  if (!chain.length) throw new ReceiptError('signed transaction is not valid')
  for (let i = 0; i < chain.length - 1; i += 1) {
    if (!chain[i].verify(chain[i + 1].publicKey)) throw new ReceiptError('signed transaction is not valid')
  }
  const anchor = chain[chain.length - 1]
  const anchored = anchor.fingerprint === APPLE_ROOT.fingerprint || anchor.verify(APPLE_ROOT.publicKey)
  if (!anchored) throw new ReceiptError('signed transaction is not valid')
  const signedOk = verifySignature(
    'sha256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    { key: chain[0].publicKey, dsaEncoding: 'ieee-p1363' },
    fromB64url(parts[2])
  )
  if (!signedOk) throw new ReceiptError('signed transaction is not valid')
  if (payload.bundleId !== BUNDLE_ID) throw new ReceiptError('signed transaction is not valid')
  return claimFrom(payload)
}

async function verifyAndroid(receipt, runtime) {
  if (!runtime.play) throw new ReceiptError('Play verification is not configured')
  const productId = String(receipt.productId || '')
  const token = String(receipt.purchaseToken || '')
  if (!productKind(productId) || !token) throw new ReceiptError('purchase token is required')
  const purchase = await runtime.play.get(productId, token)
  if (!purchase || purchase.purchaseState !== 0) throw new ReceiptError('purchase is not valid')
  return claimFrom({
    productId,
    transactionId: purchase.orderId,
    revoked: purchase.revoked === true,
  })
}

/**
 * Verify a store receipt. Fixture signatures are accepted only when a test
 * secret is injected. Production rejects {fixture:true} and unsigned blobs.
 */
export async function verifyReceipt(receipt, runtime = {}) {
  if (runtime.verifyReceipt) return runtime.verifyReceipt(receipt)
  if (receipt?.fixture === true) throw new ReceiptError('fixture receipts are not accepted')
  if (runtime.fixtureSecret && typeof receipt?.signed === 'string' && receipt.signed.startsWith('fix.')) {
    return verifyFixture(receipt.signed, runtime.fixtureSecret)
  }
  if (receipt?.platform === 'ios') return verifyApple(receipt.signedTransaction)
  if (receipt?.platform === 'android') return verifyAndroid(receipt, runtime)
  throw new ReceiptError('unknown receipt')
}
