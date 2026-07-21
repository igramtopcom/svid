import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getCustomer } from '@/api/premium'
import StatusBadge from '@/components/common/StatusBadge'
import { formatDate, formatCents } from '@/lib/utils'
import { ExternalLink } from 'lucide-react'

export default function CustomerDetail() {
  const { email } = useParams<{ email: string }>()
  const navigate = useNavigate()
  const decodedEmail = email ? decodeURIComponent(email) : ''

  const { data: customer, isLoading, error } = useQuery({
    queryKey: ['customer', decodedEmail],
    queryFn: () => getCustomer(decodedEmail),
    enabled: !!decodedEmail,
  })

  if (isLoading) {
    return <div className="flex items-center justify-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600" /></div>
  }

  if (error || !customer) {
    return (
      <div className="text-center py-12">
        <p className="text-red-600">Customer not found</p>
        <button onClick={() => navigate('/customers')} className="mt-4 text-indigo-600 hover:underline">Back to Customers</button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <button onClick={() => navigate('/customers')} className="text-gray-400 hover:text-gray-600">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{customer.contact_email}</h1>
          <p className="text-sm text-gray-500">Customer since {formatDate(customer.first_purchase)}</p>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-white rounded-xl shadow-sm border p-4">
          <p className="text-sm text-gray-500">Total Spent</p>
          <p className="text-2xl font-bold text-gray-900">{formatCents(customer.total_spent_cents)}</p>
        </div>
        <div className="bg-white rounded-xl shadow-sm border p-4">
          <p className="text-sm text-gray-500">Licenses</p>
          <p className="text-2xl font-bold text-gray-900">{customer.license_count}</p>
        </div>
        <div className="bg-white rounded-xl shadow-sm border p-4">
          <p className="text-sm text-gray-500">Active</p>
          <p className="text-2xl font-bold text-green-600">{customer.active_licenses}</p>
        </div>
        {customer.stripe_customer_id && (
          <div className="bg-white rounded-xl shadow-sm border p-4">
            <p className="text-sm text-gray-500">Stripe</p>
            <a
              href={`https://dashboard.stripe.com/customers/${customer.stripe_customer_id}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-sm text-indigo-600 hover:underline flex items-center gap-1"
            >
              View in Stripe <ExternalLink size={12} />
            </a>
          </div>
        )}
      </div>

      {/* Licenses */}
      <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
        <div className="px-6 py-4 border-b">
          <h2 className="text-lg font-semibold text-gray-900">Licenses</h2>
        </div>
        {customer.licenses.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">No licenses</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Key</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Tier</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Billing</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Expires</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {customer.licenses.map((lic) => {
                  const status = lic.cancelled_at ? 'cancelled' : lic.tier !== 'premium' ? 'inactive' : new Date(lic.expires_at) < new Date() ? 'expired' : 'active'
                  return (
                    <tr key={lic.id} className="hover:bg-gray-50 cursor-pointer"
                      onClick={() => navigate(`/licenses/${lic.id}`)}>
                      <td className="px-6 py-3 font-mono text-xs text-indigo-600">{lic.license_key.slice(0, 20)}...</td>
                      <td className="px-6 py-3">
                        <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
                          lic.tier === 'premium' ? 'bg-purple-100 text-purple-800' : 'bg-gray-100 text-gray-600'
                        }`}>{lic.tier}</span>
                      </td>
                      <td className="px-6 py-3 text-sm capitalize">{lic.billing_cycle}</td>
                      <td className="px-6 py-3"><StatusBadge status={status} /></td>
                      <td className="px-6 py-3 text-sm text-gray-500">{formatDate(lic.expires_at)}</td>
                      <td className="px-6 py-3 text-sm text-gray-500">{formatDate(lic.created_at)}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Transactions */}
      <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
        <div className="px-6 py-4 border-b">
          <h2 className="text-lg font-semibold text-gray-900">Transactions</h2>
        </div>
        {customer.transactions.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">No transactions</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">ID</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Method</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Cycle</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Amount</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {customer.transactions.map((txn) => (
                  <tr key={txn.id} className="hover:bg-gray-50 cursor-pointer"
                    onClick={() => navigate(`/transactions/${txn.id}`)}>
                    <td className="px-6 py-3 font-mono text-xs text-indigo-600">{txn.id.slice(0, 8)}...</td>
                    <td className="px-6 py-3 text-sm capitalize">{txn.payment_method}</td>
                    <td className="px-6 py-3 text-sm capitalize">{txn.billing_cycle}</td>
                    <td className="px-6 py-3 text-sm font-medium">{formatCents(txn.amount_cents)}</td>
                    <td className="px-6 py-3"><StatusBadge status={txn.status} /></td>
                    <td className="px-6 py-3 text-sm text-gray-500">{formatDate(txn.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
