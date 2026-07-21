import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Crown, Mail } from 'lucide-react'
import { getDashboardTopCustomers } from '@/api/devices'
import { useBrandStore } from '@/store/brand'
import { formatCents, timeAgo, cn } from '@/lib/utils'

// Rank badges for top 3 (gold/silver/bronze)
function RankBadge({ rank }: { rank: number }) {
  if (rank === 0) {
    return (
      <span className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-yellow-100 text-yellow-700 text-xs font-bold">
        <Crown size={12} />
      </span>
    )
  }
  if (rank === 1) {
    return (
      <span className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-gray-100 text-gray-600 text-xs font-bold">
        2
      </span>
    )
  }
  if (rank === 2) {
    return (
      <span className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-orange-100 text-orange-600 text-xs font-bold">
        3
      </span>
    )
  }
  return (
    <span className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-gray-50 text-gray-400 text-xs font-medium">
      {rank + 1}
    </span>
  )
}

export default function TopCustomers() {
  const brand = useBrandStore((s) => s.brand)

  const { data, isLoading } = useQuery({
    queryKey: ['dashboard-top-customers', brand],
    queryFn: () => getDashboardTopCustomers(10, brand || undefined),
  })

  return (
    <div className="bg-white rounded-lg border border-gray-200">
      <div className="flex items-center justify-between p-4 border-b border-gray-200">
        <div className="flex items-center gap-2">
          <Crown size={16} className="text-brand-600" />
          <h3 className="text-sm font-semibold text-gray-700">Top Customers</h3>
        </div>
        <Link to="/customers" className="text-xs text-brand-600 hover:text-brand-700">
          View all →
        </Link>
      </div>
      <div className="divide-y divide-gray-100">
        {isLoading && (
          <div className="p-8 text-center text-sm text-gray-400">Loading…</div>
        )}
        {!isLoading && (!data || data.customers.length === 0) && (
          <div className="p-8 text-center text-sm text-gray-400">No customer data yet</div>
        )}
        {data?.customers.map((c, i) => (
          <Link
            key={c.contact_email}
            to={`/customers/${encodeURIComponent(c.contact_email)}`}
            className="flex items-center gap-3 p-3 hover:bg-gray-50 transition-colors"
          >
            <RankBadge rank={i} />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-1.5 text-sm font-medium text-gray-900 truncate">
                <Mail size={12} className="text-gray-400 flex-shrink-0" />
                <span className="truncate" title={c.contact_email}>{c.contact_email}</span>
              </div>
              <div className="text-xs text-gray-500 mt-0.5">
                {c.license_count} {c.license_count === 1 ? 'license' : 'licenses'}
                {c.last_purchase && <span className="text-gray-400"> · {timeAgo(c.last_purchase)}</span>}
              </div>
            </div>
            <div className={cn('text-sm font-bold', i === 0 ? 'text-brand-600' : 'text-gray-700')}>
              {formatCents(c.total_spent_cents)}
            </div>
          </Link>
        ))}
      </div>
    </div>
  )
}
