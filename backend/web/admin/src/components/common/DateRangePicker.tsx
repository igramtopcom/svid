import { useState, useEffect, useRef } from 'react'
import { Calendar, ChevronDown } from 'lucide-react'

interface Props {
  value: number // days (e.g. 7, 30, 90)
  onChange: (days: number) => void
  presets?: { days: number; label: string }[]
  className?: string
}

const DEFAULT_PRESETS = [
  { days: 1, label: 'Today' },
  { days: 7, label: 'Last 7 days' },
  { days: 30, label: 'Last 30 days' },
  { days: 90, label: 'Last 90 days' },
  { days: 180, label: 'Last 6 months' },
  { days: 365, label: 'Last year' },
]

function formatLabel(days: number, presets: { days: number; label: string }[]): string {
  const match = presets.find((p) => p.days === days)
  if (match) return match.label
  return `Last ${days} days`
}

/**
 * DateRangePicker — day-based range selector with presets + custom input.
 * Returns the number of days (from N days ago → now).
 */
export default function DateRangePicker({
  value,
  onChange,
  presets = DEFAULT_PRESETS,
  className = '',
}: Props) {
  const [open, setOpen] = useState(false)
  const [customDays, setCustomDays] = useState<string>(String(value))
  const wrapRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    setCustomDays(String(value))
  }, [value])

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    if (open) document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [open])

  const handlePreset = (days: number) => {
    onChange(days)
    setOpen(false)
  }

  const handleCustomSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const n = parseInt(customDays, 10)
    if (!isNaN(n) && n > 0 && n <= 3650) {
      onChange(n)
      setOpen(false)
    }
  }

  return (
    <div ref={wrapRef} className={`relative inline-block ${className}`}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 px-3 py-1.5 bg-white border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors"
      >
        <Calendar size={14} className="text-gray-400" />
        {formatLabel(value, presets)}
        <ChevronDown size={14} className="text-gray-400" />
      </button>

      {open && (
        <div className="absolute right-0 mt-1 z-30 w-56 bg-white border border-gray-200 rounded-lg shadow-lg overflow-hidden">
          <div className="py-1">
            {presets.map((p) => (
              <button
                key={p.days}
                onClick={() => handlePreset(p.days)}
                className={`w-full text-left px-3 py-2 text-sm transition-colors ${
                  value === p.days
                    ? 'bg-brand-50 text-brand-600 font-medium'
                    : 'text-gray-700 hover:bg-gray-50'
                }`}
              >
                {p.label}
              </button>
            ))}
          </div>
          <div className="border-t border-gray-100 p-2">
            <form onSubmit={handleCustomSubmit} className="flex items-center gap-2">
              <span className="text-xs text-gray-500">Custom:</span>
              <input
                type="number"
                min={1}
                max={3650}
                value={customDays}
                onChange={(e) => setCustomDays(e.target.value)}
                className="flex-1 px-2 py-1 border border-gray-300 rounded text-sm w-16"
                placeholder="Days"
              />
              <button
                type="submit"
                className="px-2 py-1 bg-brand-500 text-white rounded text-xs font-medium hover:bg-brand-600 transition-colors"
              >
                Apply
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  )
}
