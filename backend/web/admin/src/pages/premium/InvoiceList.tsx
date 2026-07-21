import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listInvoices, getInvoiceStats } from '@/api/premium'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import StatusBadge from '@/components/common/StatusBadge'
import BrandBadge from '@/components/common/BrandBadge'
import { formatDate, formatDateShort, formatCents } from '@/lib/utils'
import { useDebounce } from '@/hooks/useDebounce'
import { FileText, DollarSign, CheckCircle, AlertCircle, Download } from 'lucide-react'
import SortHeader from '@/components/common/SortHeader'
import { exportCSV } from '@/lib/export'

export default function InvoiceList() {
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
    queryKey: ['invoice-stats', brand],
    queryFn: () => getInvoiceStats(brand || undefined),
  })

  const { data: invoices, isLoading } = useQuery({
    queryKey: ['invoices', page, statusFilter, debouncedSearch, sortBy, sortDir, brand],
    queryFn: () => listInvoices({
      page,
      per_page: 20,
      status: statusFilter || undefined,
      search: debouncedSearch || undefined,
      sort_by: sortBy || undefined,
      sort_dir: sortDir,
      brand: brand || undefined,
    }),
  })

  const statuses = ['open', 'paid', 'void', 'uncollectible']

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">
          Invoices<BrandBadge />
          {invoices?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({invoices.total})</span>}
        </h2>
        {invoices?.items?.length ? (
          <button
            onClick={() => exportCSV(invoices.items.map(inv => ({
              stripe_invoice_id: inv.stripe_invoice_id || '',
              email: inv.contact_email,
              status: inv.status,
              billing_reason: inv.billing_reason || '',
              amount_due: formatCents(inv.amount_due_cents),
              amount_paid: formatCents(inv.amount_paid_cents),
              paid_at: inv.paid_at || '',
              created_at: inv.created_at,
            })), 'invoices')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
          <StatsCard title="Total Invoices" value={stats.total_invoices} icon={<FileText size={24} />} />
          <StatsCard title="Total Paid" value={formatCents(stats.total_paid_cents)} icon={<DollarSign size={24} />} />
          <StatsCard title="Paid" value={stats.by_status?.paid || 0} icon={<CheckCircle size={24} />} />
          <StatsCard title="Open" value={stats.by_status?.open || 0} icon={<AlertCircle size={24} />} />
        </div>
      )}

      {/* Filters */}
      <div className="bg-white rounded-lg border border-gray-200 p-4 mb-4">
        <div className="flex flex-wrap gap-3 items-center">
          <input
            type="text"
            placeholder="Search by email or invoice ID..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            className="flex-1 min-w-[200px] px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-[#c8294f]/20 focus:border-[#c8294f]"
          />
        </div>
      </div>

      {/* Status tabs */}
      {stats?.by_status && (
        <div className="flex gap-1 mb-4 flex-wrap">
          <button
            onClick={() => { setStatusFilter(''); setPage(1) }}
            className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
              statusFilter === '' ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
            }`}
          >
            All ({stats.total_invoices})
          </button>
          {statuses.map((s) => {
            const count = stats.by_status?.[s] || 0
            if (count === 0 && statusFilter !== s) return null
            return (
              <button
                key={s}
                onClick={() => { setStatusFilter(s); setPage(1) }}
                className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
                  statusFilter === s ? 'bg-gray-900 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                {s.charAt(0).toUpperCase() + s.slice(1)} ({count})
              </button>
            )
          })}
        </div>
      )}

      {/* Table */}
      {isLoading ? (
        <SkeletonTable rows={6} />
      ) : !invoices?.items?.length ? (
        <EmptyState message="No invoices found" description="Invoices appear when Stripe processes subscription payments" />
      ) : (
        <div className="bg-white rounded-lg border border-gray-200">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
                <tr>
                  <th className="px-4 py-3 text-left">Invoice ID</th>
                  <SortHeader label="Email" field="contact_email" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  <SortHeader label="Status" field="status" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  <th className="px-4 py-3 text-left">Reason</th>
                  <th className="px-4 py-3 text-left">Period</th>
                  <SortHeader label="Amount Due" field="amount_due_cents" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} align="right" />
                  <SortHeader label="Amount Paid" field="amount_paid_cents" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} align="right" />
                  <SortHeader label="Paid At" field="paid_at" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  <SortHeader label="Created" field="created_at" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  <th className="px-4 py-3 text-center">PDF</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {invoices.items.map((inv) => (
                  <tr key={inv.id} className="hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/invoices/${inv.id}`)}>
                    <td className="px-4 py-3 font-mono text-xs">
                      <span title={inv.stripe_invoice_id}>{inv.stripe_invoice_id?.slice(0, 20)}...</span>
                    </td>
                    <td className="px-4 py-3">{inv.contact_email}</td>
                    <td className="px-4 py-3"><StatusBadge status={inv.status} /></td>
                    <td className="px-4 py-3 text-gray-500 capitalize">{inv.billing_reason?.replace(/_/g, ' ') || '-'}</td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{inv.period_start && inv.period_end ? `${formatDateShort(inv.period_start)} — ${formatDateShort(inv.period_end)}` : '-'}</td>
                    <td className="px-4 py-3 text-right font-medium">{formatCents(inv.amount_due_cents)}</td>
                    <td className="px-4 py-3 text-right font-medium">{formatCents(inv.amount_paid_cents)}</td>
                    <td className="px-4 py-3 text-gray-500">{inv.paid_at ? formatDate(inv.paid_at) : '-'}</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(inv.created_at)}</td>
                    <td className="px-4 py-3 text-center" onClick={(e) => e.stopPropagation()}>
                      {inv.invoice_pdf_url ? (
                        <a
                          href={inv.invoice_pdf_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-[#c8294f] hover:underline text-xs"
                        >
                          PDF
                        </a>
                      ) : inv.hosted_invoice_url ? (
                        <a
                          href={inv.hosted_invoice_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-blue-600 hover:underline text-xs"
                        >
                          View
                        </a>
                      ) : '-'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {invoices.total_pages > 1 && (
            <div className="p-4 border-t border-gray-200">
              <Pagination
                page={page}
                totalPages={invoices.total_pages}
                total={invoices.total}
                onPageChange={setPage}
              />
            </div>
          )}
        </div>
      )}
    </div>
  )
}
