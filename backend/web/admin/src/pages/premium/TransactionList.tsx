import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listTransactions, getTransactionStats } from '@/api/premium'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import StatusBadge from '@/components/common/StatusBadge'
import BrandBadge from '@/components/common/BrandBadge'
import { formatDate, formatCents } from '@/lib/utils'
import { useDebounce } from '@/hooks/useDebounce'
import { CreditCard, DollarSign, TrendingUp, Receipt, Download } from 'lucide-react'
import SortHeader from '@/components/common/SortHeader'
import { exportCSV } from '@/lib/export'

export default function TransactionList() {
  const navigate = useNavigate()
  const [page, setPage] = useState(1)
  const [statusFilter, setStatusFilter] = useState('')
  const [methodFilter, setMethodFilter] = useState('')
  const [search, setSearch] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
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
    queryKey: ['transaction-stats', brand],
    queryFn: () => getTransactionStats(brand || undefined),
  })

  const { data: transactions, isLoading } = useQuery({
    queryKey: ['transactions', page, statusFilter, methodFilter, debouncedSearch, dateFrom, dateTo, sortBy, sortDir, brand],
    queryFn: () => listTransactions({
      page,
      per_page: 20,
      status: statusFilter || undefined,
      payment_method: methodFilter || undefined,
      search: debouncedSearch || undefined,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
      sort_by: sortBy || undefined,
      sort_dir: sortDir,
      brand: brand || undefined,
    }),
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">
          Transactions<BrandBadge />
          {transactions?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({transactions.total})</span>}
        </h2>
        {transactions?.items?.length ? (
          <button
            onClick={() => exportCSV(transactions.items.map(t => ({
              id: t.id,
              email: t.contact_email || '',
              payment_method: t.payment_method,
              billing_cycle: t.billing_cycle,
              amount: formatCents(t.amount_cents),
              status: t.status,
              created_at: t.created_at,
            })), 'transactions')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          <StatsCard title="Total Transactions" value={stats.total_transactions} icon={<Receipt size={24} />} />
          <StatsCard title="Total Revenue" value={formatCents(stats.total_revenue_cents)} icon={<DollarSign size={24} />} />
          <StatsCard title="Revenue Today" value={formatCents(stats.revenue_today_cents)} icon={<TrendingUp size={24} />} />
          <StatsCard title="Revenue This Month" value={formatCents(stats.revenue_this_month_cents)} icon={<CreditCard size={24} />} />
        </div>
      )}

      {/* Status breakdown */}
      {stats?.by_status && Object.keys(stats.by_status).length > 0 && (
        <div className="flex gap-2 mb-4 flex-wrap">
          {Object.entries(stats.by_status).map(([status, count]) => (
            <button
              key={status}
              onClick={() => { setStatusFilter(statusFilter === status ? '' : status); setPage(1) }}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium border transition-colors ${
                statusFilter === status ? 'bg-brand-600 text-white border-brand-600' : 'bg-white text-gray-600 border-gray-200 hover:border-gray-400'
              }`}
            >
              <StatusBadge status={status} />
              <span>{count}</span>
            </button>
          ))}
        </div>
      )}

      {/* Filters */}
      <div className="bg-white rounded-lg border border-gray-200 mb-6">
        <div className="p-4 border-b border-gray-200 flex flex-wrap items-center gap-3">
          <input
            type="text"
            placeholder="Search by ID, email, or license key..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-3 py-1.5 w-64"
          />
          <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-2 py-1.5">
            <option value="">All Statuses</option>
            <option value="pending">Pending</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
            <option value="cancelled">Cancelled</option>
            <option value="refunded">Refunded</option>
          </select>
          <select value={methodFilter} onChange={(e) => { setMethodFilter(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-2 py-1.5">
            <option value="">All Methods</option>
            <option value="stripe">Stripe</option>
            <option value="crypto">Crypto</option>
          </select>
          <input type="date" value={dateFrom} onChange={(e) => { setDateFrom(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-2 py-1.5" placeholder="From" />
          <input type="date" value={dateTo} onChange={(e) => { setDateTo(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-2 py-1.5" placeholder="To" />
          {(search || statusFilter || methodFilter || dateFrom || dateTo) && (
            <button onClick={() => { setSearch(''); setStatusFilter(''); setMethodFilter(''); setDateFrom(''); setDateTo(''); setPage(1) }}
              className="text-xs text-gray-500 hover:text-gray-700">Clear filters</button>
          )}
        </div>

        {isLoading ? <SkeletonTable rows={6} /> : !transactions?.items?.length ? (
          <EmptyState message="No transactions found" description="Transactions are recorded when users initiate checkout from the app" />
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
                  <tr>
                    <th className="px-4 py-3 text-left">ID</th>
                    <th className="px-4 py-3 text-left">Email</th>
                    <th className="px-4 py-3 text-left">Method</th>
                    <th className="px-4 py-3 text-left">Cycle</th>
                    <SortHeader label="Amount" field="amount_cents" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="Status" field="status" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="Created" field="created_at" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {transactions.items.map((txn) => (
                    <tr key={txn.id} className="hover:bg-gray-50 cursor-pointer"
                      onClick={() => navigate(`/transactions/${txn.id}`)}>
                      <td className="px-4 py-3 font-mono text-xs text-indigo-600">{txn.id.slice(0, 8)}...</td>
                      <td className="px-4 py-3 text-xs text-gray-600">{txn.contact_email || '—'}</td>
                      <td className="px-4 py-3 capitalize">{txn.payment_method}</td>
                      <td className="px-4 py-3 capitalize">{txn.billing_cycle}</td>
                      <td className="px-4 py-3 font-medium">{formatCents(txn.amount_cents)}</td>
                      <td className="px-4 py-3"><StatusBadge status={txn.status} /></td>
                      <td className="px-4 py-3 text-gray-500">{formatDate(txn.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {transactions.total_pages > 1 && (
              <div className="p-4 border-t border-gray-200">
                <Pagination page={transactions.page} totalPages={transactions.total_pages} total={transactions.total} onPageChange={setPage} />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
