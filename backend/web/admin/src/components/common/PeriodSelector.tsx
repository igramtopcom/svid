interface Props {
  value: number
  onChange: (days: number) => void
  options?: number[]
}

const DEFAULT_OPTIONS = [7, 30, 90]

function label(d: number): string {
  if (d === 365) return '1Y'
  if (d >= 30 && d % 30 === 0) return `${d / 30}M`
  return `${d}D`
}

export default function PeriodSelector({ value, onChange, options = DEFAULT_OPTIONS }: Props) {
  return (
    <div className="flex gap-1 bg-gray-100 rounded-lg p-1">
      {options.map((d) => (
        <button
          key={d}
          onClick={() => onChange(d)}
          className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
            value === d ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          {label(d)}
        </button>
      ))}
    </div>
  )
}
