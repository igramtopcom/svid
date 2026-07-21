import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { listCustomers, getCustomerStats } from '@/api/premium'
import { useBrandStore } from '@/store/brand'
import StatsCard from '@/components/common/StatsCard'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import { formatDate, formatCents } from '@/lib/utils'
import { useDebounce } from '@/hooks/useDebounce'
import { Users, DollarSign, UserCheck, Download } from 'lucide-react'
import SortHeader from '@/components/common/SortHeader'
import { exportCSV } from '@/lib/export'

export default function CustomerList() {
  const navigate = useNavigate()
  const [page, setPage] = useState(1)
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
    queryKey: ['customer-stats', brand],
    queryFn: () => getCustomerStats(brand || undefined),
  })

  const { data: customers, isLoading } = useQuery({
    queryKey: ['customers', page, debouncedSearch, sortBy, sortDir, brand],
    queryFn: () => listCustomers({
      page,
      per_page: 20,
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
          Customers<BrandBadge />
          {customers?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({customers.total})</span>}
        </h2>
        {customers?.items?.length ? (
          <button
            onClick={() => exportCSV(customers.items.map(c => ({
              email: c.contact_email,
              stripe_id: c.stripe_customer_id || '',
              licenses: c.license_count,
              active_licenses: c.active_licenses,
              total_spent: formatCents(c.total_spent_cents),
              first_purchase: c.first_purchase,
              last_purchase: c.last_purchase,
            })), 'customers')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4 mb-6">
          <StatsCard title="Total Customers" value={stats.total_customers} icon={<Users size={24} />} />
          <StatsCard title="Total Revenue" value={formatCents(stats.total_revenue_cents)} icon={<DollarSign size={24} />} />
          <StatsCard title="Avg Revenue/Customer" value={formatCents(stats.avg_revenue_cents)} icon={<UserCheck size={24} />} />
        </div>
      )}

      {/* Table */}
      <div className="bg-white rounded-lg border border-gray-200">
        <div className="p-4 border-b border-gray-200">
          <input
            type="text"
            placeholder="Search by email or Stripe customer ID..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-3 py-1.5 w-80"
          />
        </div>

        {isLoading ? <SkeletonTable rows={6} /> : !customers?.items?.length ? (
          <EmptyState message="No customers found" description="Customers are created automatically when users complete a purchase" />
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
                  <tr>
                    <th className="px-4 py-3 text-left">Email</th>
                    <th className="px-4 py-3 text-left">Stripe ID</th>
                    <SortHeader label="Licenses" field="license_count" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <th className="px-4 py-3 text-left">Active</th>
                    <SortHeader label="Total Spent" field="total_spent_cents" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="First Purchase" field="first_purchase" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="Last Purchase" field="last_purchase" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {customers.items.map((customer) => (
                    <tr key={customer.contact_email} className="hover:bg-gray-50 cursor-pointer"
                      onClick={() => navigate(`/customers/${encodeURIComponent(customer.contact_email)}`)}>
                      <td className="px-4 py-3 text-indigo-600 hover:underline">{customer.contact_email}</td>
                      <td className="px-4 py-3">
                        {customer.stripe_customer_id ? (
                          <a href={`https://dashboard.stripe.com/customers/${customer.stripe_customer_id}`}
                             target="_blank" rel="noopener noreferrer"
                             onClick={(e) => e.stopPropagation()}
                             className="font-mono text-xs text-indigo-600 hover:underline">
                            {customer.stripe_customer_id}
                          </a>
                        ) : '—'}
                      </td>
                      <td className="px-4 py-3">{customer.license_count}</td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                          customer.active_licenses > 0 ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
                        }`}>
                          {customer.active_licenses}
                        </span>
                      </td>
                      <td className="px-4 py-3 font-medium">{formatCents(customer.total_spent_cents)}</td>
                      <td className="px-4 py-3 text-gray-500">{formatDate(customer.first_purchase)}</td>
                      <td className="px-4 py-3 text-gray-500">{formatDate(customer.last_purchase)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {customers.total_pages > 1 && (
              <div className="p-4 border-t border-gray-200">
                <Pagination page={customers.page} totalPages={customers.total_pages} total={customers.total} onPageChange={setPage} />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
