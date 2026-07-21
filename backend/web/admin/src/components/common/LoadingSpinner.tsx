import { Loader2 } from 'lucide-react'

export default function LoadingSpinner() {
  return (
    <div className="flex items-center justify-center py-12">
      <Loader2 className="animate-spin text-gray-400" size={32} />
    </div>
  )
}

export function SkeletonCard() {
  return (
    <div className="bg-white rounded-lg shadow p-6 animate-pulse">
      <div className="h-3 w-20 bg-gray-200 rounded mb-3" />
      <div className="h-7 w-28 bg-gray-200 rounded mb-2" />
      <div className="h-3 w-16 bg-gray-100 rounded" />
    </div>
  )
}

export function SkeletonTable({ rows = 5 }: { rows?: number }) {
  return (
    <div className="bg-white rounded-lg shadow overflow-hidden animate-pulse">
      <div className="border-b border-gray-200 px-6 py-3 flex gap-4">
        {[1, 2, 3, 4].map(i => (
          <div key={i} className="h-3 bg-gray-200 rounded flex-1" />
        ))}
      </div>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="px-6 py-4 border-b border-gray-50 flex gap-4">
          {[1, 2, 3, 4].map(j => (
            <div key={j} className="h-3 bg-gray-100 rounded flex-1" />
          ))}
        </div>
      ))}
    </div>
  )
}

export function SkeletonChart() {
  return (
    <div className="bg-white rounded-lg shadow p-6 animate-pulse">
      <div className="h-3 w-32 bg-gray-200 rounded mb-4" />
      <div className="h-48 bg-gray-100 rounded" />
    </div>
  )
}

export function PageSkeleton({ cards = 4, tableRows = 5 }: { cards?: number; tableRows?: number }) {
  return (
    <div className="space-y-6">
      <div className={`grid grid-cols-1 md:grid-cols-2 lg:grid-cols-${cards} gap-4`}>
        {Array.from({ length: cards }).map((_, i) => (
          <SkeletonCard key={i} />
        ))}
      </div>
      <SkeletonTable rows={tableRows} />
    </div>
  )
}
