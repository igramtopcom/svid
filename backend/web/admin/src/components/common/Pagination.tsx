import { ChevronLeft, ChevronRight } from 'lucide-react'

interface Props {
  page: number
  totalPages: number
  total?: number
  perPage?: number
  onPageChange: (page: number) => void
}

export default function Pagination({ page, totalPages, total, perPage = 20, onPageChange }: Props) {
  if (totalPages <= 1 && !total) return null

  const from = (page - 1) * perPage + 1
  const to = Math.min(page * perPage, total || page * perPage)

  return (
    <div className="flex items-center justify-between mt-4">
      <p className="text-sm text-gray-500">
        {total != null
          ? `Showing ${from}-${to} of ${total.toLocaleString()}`
          : `Page ${page} of ${totalPages}`}
      </p>
      {totalPages > 1 && (
        <div className="flex gap-1">
          <button
            onClick={() => onPageChange(page - 1)}
            disabled={page <= 1}
            className="p-1.5 rounded border border-gray-200 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <ChevronLeft size={16} />
          </button>
          <button
            onClick={() => onPageChange(page + 1)}
            disabled={page >= totalPages}
            className="p-1.5 rounded border border-gray-200 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            <ChevronRight size={16} />
          </button>
        </div>
      )}
    </div>
  )
}
