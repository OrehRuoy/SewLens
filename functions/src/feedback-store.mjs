import { getApps, initializeApp } from 'firebase-admin/app'
import { getFirestore } from 'firebase-admin/firestore'

function database() {
  if (!getApps().length) initializeApp()
  return getFirestore()
}

/**
 * Anonymous fit notes in fitFeedback/{auto id}.
 * The document has no install id, no measurements, and no photo.
 */
export function firestoreFeedbackStore() {
  return {
    async save(doc) {
      const stored = {
        design: doc.design,
        complaint: doc.complaint,
        option: doc.option,
        delta: doc.delta,
        locale: doc.locale,
        createdAt: doc.createdAt,
      }
      await database().collection('fitFeedback').add(stored)
    },
  }
}
