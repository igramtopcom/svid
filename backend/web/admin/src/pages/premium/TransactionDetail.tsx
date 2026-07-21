import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getTransaction, refundTransaction } from '@/api/premium'
import StatusBadge from '@/components/common/StatusBadge'
import { formatDate, formatCents } from '@/lib/utils'

export default function TransactionDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const { data: txn, isLoading, error } = useQuery({
    queryKey: ['transaction', id],
    queryFn: () => getTransaction(id!),
    enabled: !!id,
  })

  const refundMutation = useMutation({
    mutationFn: ({ cancelLicense }: { cancelLicense: boolean }) => refundTransaction(id!, cancelLicense),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['transaction', id] })
      toast.success('Transaction refunded')
    },
  })

  if (isLoading) {
    return <div className="flex items-center justify-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600" /></div>
  }

  if (error || !txn) {
    return (
      <div className="text-center py-12">
        <p className="text-red-600">Failed to load transaction</p>
        <button onClick={() => navigate('/transactions')} className="mt-4 text-indigo-600 hover:underline">Back to Transactions</button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <button onClick={() => navigate('/transactions')} className="text-gray-400 hover:text-gray-600">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Transaction Details</h1>
          <p className="text-sm text-gray-500 font-mono">{txn.id}</p>
        </div>
      </div>

      {/* Info Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white rounded-xl shadow-sm border p-6 space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">Payment Information</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-sm text-gray-500">Status</p>
              <StatusBadge status={txn.status} />
            </div>
            <div>
              <p className="text-sm text-gray-500">Amount</p>
              <p className="text-lg font-bold">{formatCents(txn.amount_cents)} {txn.currency}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Payment Method</p>
              <p className="text-sm capitalize">{txn.payment_method}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Billing Cycle</p>
              <p className="text-sm capitalize">{txn.billing_cycle}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Created</p>
              <p className="text-sm">{formatDate(txn.created_at)}</p>
            </div>
            {txn.completed_at && (
              <div>
                <p className="text-sm text-gray-500">Completed</p>
                <p className="text-sm">{formatDate(txn.completed_at)}</p>
              </div>
            )}
          </div>
        </div>

        <div className="bg-white rounded-xl shadow-sm border p-6 space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">Linked Data</h2>
          <div className="grid grid-cols-2 gap-4">
            {txn.contact_email && (
              <div>
                <p className="text-sm text-gray-500">Customer Email</p>
                <button onClick={() => navigate(`/customers/${encodeURIComponent(txn.contact_email!)}`)}
                  className="text-sm text-indigo-600 hover:underline">{txn.contact_email}</button>
              </div>
            )}
            {txn.license_key && (
              <div>
                <p className="text-sm text-gray-500">License Key</p>
                <p className="text-xs font-mono">{txn.license_key}</p>
              </div>
            )}
            {txn.license_id && (
              <div>
                <p className="text-sm text-gray-500">License ID</p>
                <button onClick={() => navigate(`/licenses/${txn.license_id}`)}
                  className="text-xs font-mono text-indigo-600 hover:underline">{txn.license_id.slice(0, 8)}...</button>
              </div>
            )}
            <div>
              <p className="text-sm text-gray-500">Device ID</p>
              <p className="text-xs font-mono break-all">{txn.device_id}</p>
            </div>
            {txn.stripe_session_id && (
              <div>
                <p className="text-sm text-gray-500">Stripe Session</p>
                <p className="text-xs font-mono break-all">{txn.stripe_session_id}</p>
              </div>
            )}
            {txn.crypto_invoice_id && (
              <div>
                <p className="text-sm text-gray-500">Crypto Invoice</p>
                <p className="text-xs font-mono break-all">{txn.crypto_invoice_id}</p>
              </div>
            )}
            {txn.error_message && (
              <div className="col-span-2">
                <p className="text-sm text-gray-500">Error</p>
                <p className="text-sm text-red-600">{txn.error_message}</p>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Refund Action */}
      {txn.status === 'completed' && (
        <div className="bg-red-50 rounded-xl border border-red-200 p-6">
          <h3 className="text-lg font-semibold text-red-900">Refund Transaction</h3>
          <p className="text-sm text-red-700 mt-1">Issue a refund for this transaction. This cannot be undone.</p>
          <div className="flex gap-3 mt-3">
            <button
              onClick={() => {
                if (confirm('Refund this transaction?')) {
                  refundMutation.mutate({ cancelLicense: false })
                }
              }}
              disabled={refundMutation.isPending}
              className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 text-sm disabled:opacity-50"
            >
              {refundMutation.isPending ? 'Processing...' : 'Refund Only'}
            </button>
            <button
              onClick={() => {
                if (confirm('Refund AND cancel the associated license?')) {
                  refundMutation.mutate({ cancelLicense: true })
                }
              }}
              disabled={refundMutation.isPending}
              className="px-4 py-2 bg-red-800 text-white rounded-lg hover:bg-red-900 text-sm disabled:opacity-50"
            >
              Refund + Cancel License
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
