import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listSubscriptions, getSubscriptionStats, getMRRTrend } from '@/api/premium'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import StatusBadge from '@/components/common/StatusBadge'
import BrandBadge from '@/components/common/BrandBadge'
import { formatDate, formatCents } from '@/lib/utils'
import { useDebounce } from '@/hooks/useDebounce'
import { Repeat, CheckCircle, XCircle, Clock, DollarSign, TrendingDown, Download } from 'lucide-react'
import SortHeader from '@/components/common/SortHeader'
import { exportCSV } from '@/lib/export'
import {
  LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts'

const STATUS_TABS = [
  { key: '', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'cancelled', label: 'Cancelled' },
  { key: 'expired', label: 'Expired' },
]

export default function SubscriptionList() {
  const navigate = useNavigate()
  const [page, setPage] = useState(1)
  const [statusFilter, setStatusFilter] = useState('')
  const [search, setSearch] = useState('')
  const brand = useBrandStore((s) => s.brand)
  const [sortBy, setSortBy] = useState('')
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc')
  const debouncedSearch = useDebounce(search, 300)

  const handleSort = (field: string) => {
    if (sortBy === field) {
      setSortDir(d => d === 'asc' ? 'desc' : 'asc')
    } else {
      setSortBy(field)
      setSortDir('desc')
    }
    setPage(1)
  }

  const { data: stats } = useQuery({
    queryKey: ['subscription-stats', brand],
    queryFn: () => getSubscriptionStats(brand || undefined),
  })

  const { data: mrrTrend } = useQuery({
    queryKey: ['mrr-trend', brand],
    queryFn: () => getMRRTrend(12, brand || undefined),
  })

  const { data: subscriptions, isLoading } = useQuery({
    queryKey: ['subscriptions', page, statusFilter, debouncedSearch, sortBy, sortDir, brand],
    queryFn: () => listSubscriptions({
      page,
      per_page: 20,
      status: statusFilter || undefined,
      search: debouncedSearch || undefined,
      sort_by: sortBy || undefined,
      sort_dir: sortDir,
      brand: brand || undefined,
    }),
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">
          Subscriptions<BrandBadge />
          {subscriptions?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({subscriptions.total})</span>}
        </h2>
        {subscriptions?.items?.length ? (
          <button
            onClick={() => exportCSV(subscriptions.items.map(s => ({
              license_key: s.license_key,
              email: s.contact_email || '',
              billing_cycle: s.billing_cycle,
              payment_method: s.payment_method,
              devices: `${s.device_count}/${s.max_devices}`,
              status: s.status,
              expires_at: s.expires_at,
              created_at: s.created_at,
            })), 'subscriptions')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4 mb-6">
          <StatsCard title="Total" value={stats.total_count} icon={<Repeat size={24} />} />
          <StatsCard title="Active" value={stats.active_count} icon={<CheckCircle size={24} />} />
          <StatsCard title="Cancelled" value={stats.cancelled_count} icon={<XCircle size={24} />} />
          <StatsCard title="Expired" value={stats.expired_count} icon={<Clock size={24} />} />
          <StatsCard title="MRR" value={formatCents(stats.mrr_cents)} icon={<DollarSign size={24} />} />
          <StatsCard title="Churn Rate" value={`${(stats.churn_rate * 100).toFixed(1)}%`} icon={<TrendingDown size={24} />} />
        </div>
      )}

      {/* MRR Trend Chart */}
      {mrrTrend && mrrTrend.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-5 mb-6">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">MRR Trend (last 12 months)</h3>
          <ResponsiveContainer width="100%" height={280}>
            <LineChart data={mrrTrend.map((p) => ({
              month: p.month,
              revenue: p.amount_cents / 100,
              invoices: p.count,
            }))}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis dataKey="month" fontSize={12} />
              <YAxis fontSize={12} tickFormatter={(v) => `$${v}`} />
              <Tooltip
                formatter={(value: number, name: string) => {
                  if (name === 'revenue') return [`$${value.toFixed(2)}`, 'Revenue']
                  return [value, 'Invoices']
                }}
                labelFormatter={(label) => `Month: ${label}`}
              />
              <Line type="monotone" dataKey="revenue" stroke="#c8294f" strokeWidth={2} dot={{ r: 4, fill: '#c8294f' }} activeDot={{ r: 6 }} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Status Tabs */}
      <div className="flex gap-1 mb-4 bg-gray-100 rounded-lg p-1 w-fit">
        {STATUS_TABS.map((tab) => (
          <button
            key={tab.key}
            onClick={() => { setStatusFilter(tab.key); setPage(1) }}
            className={`px-4 py-1.5 rounded-md text-sm font-medium transition-colors ${
              statusFilter === tab.key ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            {tab.label}
            {stats && tab.key === 'active' && ` (${stats.active_count})`}
            {stats && tab.key === 'cancelled' && ` (${stats.cancelled_count})`}
            {stats && tab.key === 'expired' && ` (${stats.expired_count})`}
          </button>
        ))}
      </div>

      {/* Table */}
      <div className="bg-white rounded-lg border border-gray-200">
        <div className="p-4 border-b border-gray-200">
          <input
            type="text"
            placeholder="Search by license key or email..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-3 py-1.5 w-64"
          />
        </div>

        {isLoading ? <SkeletonTable rows={6} /> : !subscriptions?.items?.length ? (
          <EmptyState message="No subscriptions found" description="Subscriptions appear when users purchase monthly or yearly premium plans" />
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
                  <tr>
                    <SortHeader label="Email" field="contact_email" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <th className="px-4 py-3 text-left">License Key</th>
                    <SortHeader label="Billing" field="billing_cycle" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <th className="px-4 py-3 text-left">Method</th>
                    <th className="px-4 py-3 text-left">Devices</th>
                    <SortHeader label="Status" field="status" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="Expires" field="expires_at" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="Created" field="created_at" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {subscriptions.items.map((sub) => (
                    <tr key={sub.id} className="hover:bg-gray-50 cursor-pointer"
                      onClick={() => navigate(`/licenses/${sub.id}`)}>
                      <td className="px-4 py-3 text-xs text-gray-600">{sub.contact_email || '—'}</td>
                      <td className="px-4 py-3 font-mono text-xs text-indigo-600"><span title={sub.license_key}>{sub.license_key.slice(0, 16)}...</span></td>
                      <td className="px-4 py-3 capitalize">{sub.billing_cycle}</td>
                      <td className="px-4 py-3 capitalize">{sub.payment_method}</td>
                      <td className="px-4 py-3">{sub.device_count}/{sub.max_devices}</td>
                      <td className="px-4 py-3"><StatusBadge status={sub.status} /></td>
                      <td className="px-4 py-3 text-gray-500">{formatDate(sub.expires_at)}</td>
                      <td className="px-4 py-3 text-gray-500">{formatDate(sub.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {subscriptions.total_pages > 1 && (
              <div className="p-4 border-t border-gray-200">
                <Pagination page={subscriptions.page} totalPages={subscriptions.total_pages} total={subscriptions.total} onPageChange={setPage} />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
