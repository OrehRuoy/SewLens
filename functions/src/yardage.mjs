/** Shelf-pack piece boxes onto 112 cm and 150 cm fabric. */

const GAP_MM = 10

function shelfLength(pieces, widthMm) {
  const items = [...pieces].sort((a, b) => a.name.localeCompare(b.name))
  let x = 0
  let y = 0
  let rowHeight = 0
  for (const item of items) {
    const width = item.width + GAP_MM
    const height = item.height + GAP_MM
    if (x > 0 && x + width > widthMm) {
      y += rowHeight
      x = 0
      rowHeight = 0
    }
    x += width
    rowHeight = Math.max(rowHeight, height)
  }
  return y + rowHeight
}

export function estimateYardage(pieces) {
  const widths = [
    { fabricCm: 112, fabricIn: 45 },
    { fabricCm: 150, fabricIn: 60 },
  ]
  return widths.map((fabric) => {
    const lengthMm = shelfLength(pieces, fabric.fabricCm * 10)
    return {
      fabricCm: fabric.fabricCm,
      fabricIn: fabric.fabricIn,
      lengthMm: Math.round(lengthMm * 10) / 10,
    }
  })
}
