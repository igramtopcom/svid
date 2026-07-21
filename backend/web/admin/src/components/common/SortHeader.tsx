import { ChevronUp, ChevronDown, ChevronsUpDown } from 'lucide-react'

interface SortHeaderProps {
  label: string
  field: string
  currentSort: string
  currentDir: string
  onSort: (field: string) => void
  className?: string
  align?: 'left' | 'right'
}

export default function SortHeader({ label, field, currentSort, currentDir, onSort, className = '', align = 'left' }: SortHeaderProps) {
  const isActive = currentSort === field
  return (
    <th
      className={`px-4 py-3 font-medium cursor-pointer hover:bg-gray-100 select-none ${align === 'right' ? 'text-right' : 'text-left'} ${className}`}
      onClick={() => onSort(field)}
    >
      <span className={`inline-flex items-center gap-1 ${align === 'right' ? 'flex-row-reverse' : ''}`}>
        {label}
        {isActive ? (
          currentDir === 'asc' ? <ChevronUp size={14} /> : <ChevronDown size={14} />
        ) : (
          <ChevronsUpDown size={14} className="text-gray-300" />
        )}
      </span>
    </th>
  )
}
