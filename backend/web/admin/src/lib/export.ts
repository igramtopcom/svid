/**
 * Export an array of objects as a CSV file download.
 */
export function exportCSV<T extends Record<string, unknown>>(data: T[], filename: string) {
  if (!data.length) return

  const keys = Object.keys(data[0])
  const header = keys.join(',')
  const rows = data.map((row) =>
    keys.map((k) => {
      const val = row[k]
      if (val == null) return ''
      const str = String(val)
      // Escape commas, quotes, newlines
      if (str.includes(',') || str.includes('"') || str.includes('\n')) {
        return `"${str.replace(/"/g, '""')}"`
      }
      return str
    }).join(',')
  )

  const csv = [header, ...rows].join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${filename}_${new Date().toISOString().slice(0, 10)}.csv`
  link.click()
  URL.revokeObjectURL(url)
}
