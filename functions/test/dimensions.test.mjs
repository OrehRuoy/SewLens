import { draftPattern } from '../src/draft-pattern.mjs'
import { DESIGNS } from '../src/designs.mjs'
import { applyComplaint, complaintsForDesign } from '../src/fit-feedback.mjs'
import {
  chestLineLength,
  cutWidthAtChest,
  outerSideLength,
  seamBox,
  seamEdgeWidth,
  seamMaxY,
  sumLengths,
} from '../src/geometry.mjs'

const BASE_MM = {
  ankle: 240,
  biceps: 320,
  bustFront: 480,
  bustPointToUnderbust: 90,
  bustSpan: 190,
  chest: 960,
  crossSeam: 720,
  crossSeamFront: 360,
  head: 580,
  heel: 330,
  highBustFront: 460,
  highBust: 900,
  hips: 980,
  hpsToBust: 270,
  hpsToWaistBack: 450,
  hpsToWaistFront: 440,
  inseam: 780,
  knee: 380,
  neck: 380,
  seat: 1000,
  seatBack: 520,
  crotchDepth: 280,
  shoulderSlope: 13,
  shoulderToElbow: 360,
  shoulderToShoulder: 420,
  shoulderToWrist: 620,
  underbust: 800,
  upperLeg: 580,
  waist: 820,
  waistBack: 420,
  waistToArmpit: 210,
  waistToFloor: 1080,
  waistToHips: 140,
  waistToKnee: 560,
  waistToSeat: 220,
  waistToUnderbust: 100,
  waistToUpperLeg: 280,
  wrist: 170,
}

function measurementsFor(factor) {
  const measurements = {}
  for (const [key, value] of Object.entries(BASE_MM)) {
    measurements[key] = key === 'shoulderSlope' ? value : Math.round(value * factor) / 10
  }
  return measurements
}

const SETS = [0.95, 1, 1.05]

function near(actual, expected, tolerance, label) {
  const delta = Math.abs(actual - expected)
  if (delta > tolerance) {
    throw new Error(`${label}: ${actual.toFixed(2)} vs ${expected.toFixed(2)} (delta ${delta.toFixed(2)} mm, allowed ${tolerance})`)
  }
}

const CHECKS = [
  { id: 'aaron', front: ['aaron.front'], back: ['aaron.back'], chest: true, side: true },
  { id: 'brian', front: ['brian.front'], back: ['brian.back'], chest: true, cut: true, side: true },
  { id: 'bent', front: ['brian.front'], back: ['brian.back'], chest: true, side: true },
  { id: 'teagan', front: ['teagan.front'], back: ['teagan.back'], chest: true, side: true },
  { id: 'hugo', front: ['hugo.front'], back: ['hugo.back'], chest: true, cut: true, side: true },
  { id: 'simon', front: ['simon.frontRight'], back: ['simon.back'], chest: true, side: true },
  { id: 'simone', front: ['simon.frontRight'], back: ['simon.back'], chest: true, basis: 'highBust' },
  { id: 'wahid', front: ['wahid.front'], back: ['wahid.back'], side: true },
  { id: 'charlie', front: ['charlie.front'], back: ['charlie.back'], side: true, hemBack: true },
  { id: 'titan', front: ['titan.front'], back: ['titan.back'], hem: true },
  { id: 'lily', front: ['lily.front'], back: ['lily.back'], hem: true },
  { id: 'jaeger', front: ['jaeger.front'], back: ['jaeger.frontFacing'], side: true },
]

function assertChecked(check, result, tolerance = {}) {
  const { svg, appliedOptions, measurementsMm, seamAllowanceMm } = result
  const ease = appliedOptions.chestEase || 0
  const stretch = appliedOptions.stretchFactor || 0
  const basis = measurementsMm[check.basis || 'chest']
  const expectedSeam = (basis * (1 + ease) * (1 - stretch)) / 2
  if (check.chest) {
    const seam = sumLengths(svg, [...check.front, ...check.back], chestLineLength)
    near(seam, expectedSeam, 2, `${check.id} chest seam`)
  }
  if (check.cut) {
    const cut = sumLengths(svg, [...check.front, ...check.back], cutWidthAtChest)
    near(cut, expectedSeam + 2 * seamAllowanceMm, tolerance.cut ?? 2, `${check.id} chest cut width`)
  }
  if (check.side) {
    const front = sumLengths(svg, check.front, outerSideLength)
    const back = sumLengths(svg, check.back, outerSideLength)
    near(front, back, tolerance.side ?? 1, `${check.id} side seams`)
  }
  const hemTarget = measurementsMm.waistToFloor * (1 + (appliedOptions.lengthBonus || 0))
  const hems = check.hem ? [...check.front, ...check.back] : check.hemBack ? check.back : []
  for (const part of hems) {
    near(seamMaxY(svg, part), hemTarget, 2, `${check.id} ${part} hem`)
  }
}

describe('pattern dimensions from the SVG', () => {
  test.each(CHECKS.map((check) => [check.id, check]))('%s matches the inputs', async (_name, check) => {
    for (const factor of SETS) {
      const result = await draftPattern(
        {
          design: check.id,
          measurements: measurementsFor(factor),
          units: 'metric',
          locale: 'en',
          paper: 'a4',
        },
        { pdf: false }
      )
      assertChecked(check, result)
    }
  })
})

describe('fit feedback keeps the dimension checks', () => {
  test.each(CHECKS.map((check) => [check.id, check]))('%s after each fit delta', async (_name, check) => {
    const measurements = measurementsFor(1)
    const input = { design: check.id, measurements, units: 'metric', locale: 'en', paper: 'a4' }
    const base = await draftPattern(input, { pdf: false })
    assertChecked(check, base)
    const complaints = complaintsForDesign(DESIGNS[check.id])
    expect(complaints.length).toBeGreaterThan(0)
    for (const complaint of complaints) {
      const options = applyComplaint(DESIGNS[check.id], base.appliedOptions, complaint.id)
      const result = await draftPattern({ ...input, options }, { pdf: false })
      assertChecked(check, result, { cut: 3, side: 2 })
    }
  }, 180000)
})

async function draftSet(design, factor) {
  return draftPattern(
    {
      design,
      measurements: measurementsFor(factor),
      units: 'metric',
      locale: 'en',
      paper: 'a4',
    },
    { pdf: false }
  )
}

describe('remaining designs match their inputs', () => {
  test('bella back length and sleeve length', async () => {
    for (const factor of SETS) {
      const result = await draftSet('bella', factor)
      near(seamBox(result.svg, 'bella.back').height, result.measurementsMm.hpsToWaistBack, 2, 'bella back')
      near(seamBox(result.svg, 'bella.sleeve').height, result.measurementsMm.shoulderToWrist, 2, 'bella sleeve')
    }
  })

  test('paco waistband matches the seat', async () => {
    for (const factor of SETS) {
      const result = await draftSet('paco', factor)
      const box = seamBox(result.svg, 'paco.waistband')
      near(Math.max(box.width, box.height), result.measurementsMm.seat, 2, 'paco waistband')
    }
  })

  test('penelope waistband and side seams', async () => {
    for (const factor of SETS) {
      const result = await draftSet('penelope', factor)
      const box = seamBox(result.svg, 'penelope.waistband')
      const ease = result.appliedOptions.waistEase || 0
      near(Math.max(box.width, box.height), (result.measurementsMm.waist * (1 + ease)) / 2, 2, 'penelope waistband')
      near(seamMaxY(result.svg, 'penelope.front'), seamMaxY(result.svg, 'penelope.back'), 1, 'penelope hems')
    }
  })

  test('sandy waistband follows waist, hips, and overlap', async () => {
    for (const factor of SETS) {
      const result = await draftSet('sandy', factor)
      const { waistbandPosition, waistbandOverlap } = result.appliedOptions
      const { waist, hips } = result.measurementsMm
      const top = waistbandPosition * hips + (1 - waistbandPosition) * waist
      const expected = top + top * waistbandOverlap
      near(seamBox(result.svg, 'sandy.waistband').width, expected, 2, 'sandy waistband')
      const skirt = seamBox(result.svg, 'sandy.skirt')
      near(skirt.width, skirt.height, 1, 'sandy circle')
    }
  })

  test('bruce front hip width', async () => {
    for (const factor of SETS) {
      const result = await draftSet('bruce', factor)
      const scale = 1 / (1 + result.appliedOptions.stretch)
      const expected = result.measurementsMm.hips * scale * result.appliedOptions.hipRatioFront
      near(seamEdgeWidth(result.svg, 'bruce.front', 'top'), expected, 2, 'bruce front')
    }
  })

  test('florent cap width follows the head', async () => {
    for (const factor of SETS) {
      const result = await draftSet('florent', factor)
      const expected = result.measurementsMm.head * (1 + result.appliedOptions.headEase) * 0.654
      near(seamBox(result.svg, 'florent.top').width, expected, 2, 'florent top')
    }
  })

  test('trayvon tie blades match', async () => {
    for (const factor of SETS) {
      const result = await draftSet('trayvon', factor)
      near(seamMaxY(result.svg, 'trayvon.fabricTail'), seamMaxY(result.svg, 'trayvon.fabricTip'), 2, 'trayvon blades')
    }
  })

  test('umbra front width tracks the hips', async () => {
    for (const factor of SETS) {
      const result = await draftSet('umbra', factor)
      const width = chestLineLength(result.svg, 'umbra.front')
      near(width, result.measurementsMm.hips * 0.4, 2, 'umbra front')
    }
  })
})

function assertRemaining(design, result) {
  if (design === 'bella') {
    const bonus = result.appliedOptions.sleeveLengthBonus || 0
    near(seamBox(result.svg, 'bella.back').height, result.measurementsMm.hpsToWaistBack, 2, 'bella back')
    near(seamBox(result.svg, 'bella.sleeve').height, result.measurementsMm.shoulderToWrist * (1 + bonus), 2, 'bella sleeve')
  } else if (design === 'paco') {
    const box = seamBox(result.svg, 'paco.waistband')
    near(Math.max(box.width, box.height), result.measurementsMm.seat, 2, 'paco waistband')
  } else if (design === 'penelope') {
    const box = seamBox(result.svg, 'penelope.waistband')
    const ease = result.appliedOptions.waistEase || 0
    near(Math.max(box.width, box.height), (result.measurementsMm.waist * (1 + ease)) / 2, 2, 'penelope waistband')
    near(seamMaxY(result.svg, 'penelope.front'), seamMaxY(result.svg, 'penelope.back'), 1, 'penelope hems')
  } else if (design === 'sandy') {
    const { waistbandPosition, waistbandOverlap } = result.appliedOptions
    const { waist, hips } = result.measurementsMm
    const top = waistbandPosition * hips + (1 - waistbandPosition) * waist
    const expected = top + top * waistbandOverlap
    near(seamBox(result.svg, 'sandy.waistband').width, expected, 2, 'sandy waistband')
    const skirt = seamBox(result.svg, 'sandy.skirt')
    near(skirt.width, skirt.height, 1, 'sandy circle')
  } else if (design === 'bruce') {
    const scale = 1 / (1 + result.appliedOptions.stretch)
    const expected = result.measurementsMm.hips * scale * result.appliedOptions.hipRatioFront
    near(seamEdgeWidth(result.svg, 'bruce.front', 'top'), expected, 2, 'bruce front')
  } else if (design === 'florent') {
    const expected = result.measurementsMm.head * (1 + result.appliedOptions.headEase) * 0.654
    near(seamBox(result.svg, 'florent.top').width, expected, 2, 'florent top')
  } else if (design === 'trayvon') {
    near(seamMaxY(result.svg, 'trayvon.fabricTail'), seamMaxY(result.svg, 'trayvon.fabricTip'), 2, 'trayvon blades')
  } else if (design === 'umbra') {
    const base = (DESIGNS.umbra.patternConfig.options.xStretch.pct ?? 0) / 100
    const applied = result.appliedOptions.xStretch ?? base
    const expected = result.measurementsMm.hips * 0.4 * (1 + base) / (1 + applied)
    near(chestLineLength(result.svg, 'umbra.front'), expected, 2, 'umbra front')
  }
}

describe('fit feedback keeps the remaining dimension checks', () => {
  const ids = ['bella', 'paco', 'penelope', 'sandy', 'bruce', 'florent', 'trayvon', 'umbra']
  test.each(ids)('%s after each fit delta', async (design) => {
    const base = await draftSet(design, 1)
    assertRemaining(design, base)
    for (const complaint of complaintsForDesign(DESIGNS[design])) {
      const options = applyComplaint(DESIGNS[design], base.appliedOptions, complaint.id)
      const result = await draftPattern(
        {
          design,
          measurements: measurementsFor(1),
          options,
          units: 'metric',
          locale: 'en',
          paper: 'a4',
        },
        { pdf: false }
      )
      assertRemaining(design, result)
    }
  }, 180000)
})
