import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listLicenses, createLicense } from '@/api/premium'
import { useBrandStore } from '@/store/brand'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import StatusBadge from '@/components/common/StatusBadge'
import BrandBadge from '@/components/common/BrandBadge'
import Modal from '@/components/common/Modal'
import { formatDate } from '@/lib/utils'
import { useDebounce } from '@/hooks/useDebounce'
import { KeyRound, Plus, Copy, Check, Download } from 'lucide-react'
import SortHeader from '@/components/common/SortHeader'
import { exportCSV } from '@/lib/export'

const PLAN_LABELS: Record<string, string> = {
  monthly: 'Monthly',
  yearly: 'Yearly',
  lifetime1: 'Lifetime Solo (1 device)',
  lifetime2: 'Lifetime Family (3 devices)',
  lifetime3: 'Lifetime Team (10 devices)',
}

export default function LicenseKeyList() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const brand = useBrandStore((s) => s.brand)
  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const [tierFilter, setTierFilter] = useState('')
  const [methodFilter, setMethodFilter] = useState('')
  const [showCreate, setShowCreate] = useState(false)
  const [createForm, setCreateForm] = useState({ billing_cycle: 'lifetime1', contact_email: '', notes: '' })
  const [copiedKey, setCopiedKey] = useState<string | null>(null)
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

  const { data: licenses, isLoading } = useQuery({
    queryKey: ['licenses', page, debouncedSearch, tierFilter, methodFilter, sortBy, sortDir, brand],
    queryFn: () => listLicenses({
      page,
      per_page: 20,
      search: debouncedSearch || undefined,
      tier: tierFilter || undefined,
      payment_method: methodFilter || undefined,
      sort_by: sortBy || undefined,
      sort_dir: sortDir,
      brand: brand || undefined,
    }),
  })

  const createMutation = useMutation({
    mutationFn: () => createLicense({
      billing_cycle: createForm.billing_cycle,
      contact_email: createForm.contact_email || undefined,
      notes: createForm.notes || undefined,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['licenses'] })
      setShowCreate(false)
      setCreateForm({ billing_cycle: 'lifetime1', contact_email: '', notes: '' })
      toast.success('License created')
    },
  })

  const handleCopy = (key: string) => {
    navigator.clipboard.writeText(key)
    setCopiedKey(key)
    setTimeout(() => setCopiedKey(null), 2000)
  }

  const getStatus = (lic: { tier: string; cancelled_at?: string; expires_at: string }) => {
    if (lic.cancelled_at) return 'cancelled'
    if (lic.tier !== 'premium') return 'inactive'
    if (new Date(lic.expires_at) < new Date()) return 'expired'
    return 'active'
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold flex items-center gap-2">
          <KeyRound size={24} />
          License Keys<BrandBadge />
          {licenses?.total != null && <span className="text-sm font-normal text-gray-400">({licenses.total})</span>}
        </h2>
        <div className="flex items-center gap-2">
          {licenses?.items?.length ? (
            <button
              onClick={() => exportCSV(licenses.items.map(l => ({
                license_key: l.license_key,
                tier: l.tier,
                billing_cycle: l.billing_cycle,
                email: l.contact_email || '',
                payment_method: l.payment_method,
                status: l.cancelled_at ? 'cancelled' : l.tier !== 'premium' ? 'inactive' : new Date(l.expires_at) < new Date() ? 'expired' : 'active',
                expires_at: l.expires_at,
                created_at: l.created_at,
              })), 'licenses')}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
            >
              <Download size={14} /> Export
            </button>
          ) : null}
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-2 px-4 py-2 bg-brand-600 text-white rounded-lg hover:bg-brand-700 text-sm"
          >
            <Plus size={16} />
            Create License
          </button>
        </div>
      </div>

      {/* Table */}
      <div className="bg-white rounded-lg border border-gray-200">
        <div className="p-4 border-b border-gray-200 flex flex-wrap items-center gap-3">
          <input
            type="text"
            placeholder="Search by license key or email..."
            value={search}
            onChange={(e) => { setSearch(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-3 py-1.5 w-64"
          />
          <select value={tierFilter} onChange={(e) => { setTierFilter(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-2 py-1.5">
            <option value="">All Tiers</option>
            <option value="premium">Premium</option>
            <option value="free">Free</option>
          </select>
          <select value={methodFilter} onChange={(e) => { setMethodFilter(e.target.value); setPage(1) }}
            className="text-sm border border-gray-300 rounded px-2 py-1.5">
            <option value="">All Methods</option>
            <option value="stripe">Stripe</option>
            <option value="crypto">Crypto</option>
            <option value="manual">Manual</option>
          </select>
          {(search || tierFilter || methodFilter) && (
            <button onClick={() => { setSearch(''); setTierFilter(''); setMethodFilter(''); setPage(1) }} className="text-xs text-gray-500 hover:text-gray-700">
              Clear filters
            </button>
          )}
        </div>

        {isLoading ? <SkeletonTable rows={6} /> : !licenses?.items?.length ? (
          <EmptyState message="No license keys found" description="License keys are created when users purchase premium or via manual creation" />
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-gray-500 uppercase text-xs">
                  <tr>
                    <th className="px-4 py-3 text-left">Key</th>
                    <SortHeader label="Tier" field="tier" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="Billing" field="billing_cycle" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <th className="px-4 py-3 text-left">Email</th>
                    <SortHeader label="Method" field="payment_method" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <th className="px-4 py-3 text-left">Status</th>
                    <SortHeader label="Expires" field="expires_at" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                    <SortHeader label="Created" field="created_at" currentSort={sortBy} currentDir={sortDir} onSort={handleSort} />
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {licenses.items.map((lic) => {
                    const status = getStatus(lic)
                    return (
                      <tr key={lic.id} className="hover:bg-gray-50 cursor-pointer"
                        onClick={() => navigate(`/licenses/${lic.id}`)}>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-1">
                            <span title={lic.license_key} className="font-mono text-xs text-indigo-600">{lic.license_key.slice(0, 20)}...</span>
                            <button
                              onClick={(e) => { e.stopPropagation(); handleCopy(lic.license_key) }}
                              className="text-gray-400 hover:text-gray-600"
                            >
                              {copiedKey === lic.license_key ? <Check size={14} className="text-green-500" /> : <Copy size={14} />}
                            </button>
                          </div>
                        </td>
                        <td className="px-4 py-3">
                          <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                            lic.tier === 'premium' ? 'bg-purple-100 text-purple-800' : 'bg-gray-100 text-gray-600'
                          }`}>{lic.tier}</span>
                        </td>
                        <td className="px-4 py-3 capitalize">{lic.billing_cycle}</td>
                        <td className="px-4 py-3 text-xs text-gray-600">{lic.contact_email || '—'}</td>
                        <td className="px-4 py-3 capitalize">{lic.payment_method}</td>
                        <td className="px-4 py-3"><StatusBadge status={status} /></td>
                        <td className="px-4 py-3 text-gray-500">{formatDate(lic.expires_at)}</td>
                        <td className="px-4 py-3 text-gray-500">{formatDate(lic.created_at)}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
            {licenses.total_pages > 1 && (
              <div className="p-4 border-t border-gray-200">
                <Pagination page={licenses.page} totalPages={licenses.total_pages} total={licenses.total} onPageChange={setPage} />
              </div>
            )}
          </>
        )}
      </div>

      {/* Create License Modal */}
      <Modal open={showCreate} title="Create License" onClose={() => setShowCreate(false)}>
        <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Billing Cycle</label>
              <select value={createForm.billing_cycle} onChange={(e) => setCreateForm({ ...createForm, billing_cycle: e.target.value })}
                className="w-full text-sm border border-gray-300 rounded px-3 py-2">
                {Object.entries(PLAN_LABELS).map(([value, label]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Contact Email (optional)</label>
              <input
                type="email"
                value={createForm.contact_email}
                onChange={(e) => setCreateForm({ ...createForm, contact_email: e.target.value })}
                placeholder="customer@example.com"
                className="w-full text-sm border border-gray-300 rounded px-3 py-2"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Notes (optional)</label>
              <input
                type="text"
                value={createForm.notes}
                onChange={(e) => setCreateForm({ ...createForm, notes: e.target.value })}
                placeholder="Comp license for beta tester..."
                className="w-full text-sm border border-gray-300 rounded px-3 py-2"
              />
            </div>
            <div className="flex gap-3 justify-end">
              <button onClick={() => setShowCreate(false)}
                className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800">Cancel</button>
              <button onClick={() => createMutation.mutate()}
                disabled={createMutation.isPending}
                className="px-4 py-2 bg-brand-600 text-white rounded-lg hover:bg-brand-700 text-sm disabled:opacity-50">
                {createMutation.isPending ? 'Creating...' : 'Create License'}
              </button>
            </div>
          </div>
      </Modal>
    </div>
  )
}
