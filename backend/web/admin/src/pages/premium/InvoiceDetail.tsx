import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getInvoice } from '@/api/premium'
import StatusBadge from '@/components/common/StatusBadge'
import { formatDate, formatDateShort, formatCents } from '@/lib/utils'

export default function InvoiceDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()

  const { data: inv, isLoading, error } = useQuery({
    queryKey: ['invoice', id],
    queryFn: () => getInvoice(id!),
    enabled: !!id,
  })

  if (isLoading) {
    return <div className="flex items-center justify-center h-64"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600" /></div>
  }

  if (error || !inv) {
    return (
      <div className="text-center py-12">
        <p className="text-red-600">Failed to load invoice</p>
        <button onClick={() => navigate('/invoices')} className="mt-4 text-indigo-600 hover:underline">Back to Invoices</button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <button onClick={() => navigate('/invoices')} className="text-gray-400 hover:text-gray-600">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-gray-900">Invoice Details</h1>
          <p className="text-sm text-gray-500 font-mono">{inv.stripe_invoice_id}</p>
        </div>
        <StatusBadge status={inv.status} />
      </div>

      {/* Info Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Payment Info */}
        <div className="bg-white rounded-xl shadow-sm border p-6 space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">Payment Information</h2>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-sm text-gray-500">Amount Due</p>
              <p className="text-lg font-bold">{formatCents(inv.amount_due_cents)} {inv.currency.toUpperCase()}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Amount Paid</p>
              <p className="text-lg font-bold">{formatCents(inv.amount_paid_cents)} {inv.currency.toUpperCase()}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Billing Reason</p>
              <p className="text-sm capitalize">{inv.billing_reason?.replace(/_/g, ' ') || '-'}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Currency</p>
              <p className="text-sm uppercase">{inv.currency}</p>
            </div>
            {inv.period_start && inv.period_end && (
              <div className="col-span-2">
                <p className="text-sm text-gray-500">Billing Period</p>
                <p className="text-sm">{formatDateShort(inv.period_start)} &mdash; {formatDateShort(inv.period_end)}</p>
              </div>
            )}
            {inv.paid_at && (
              <div>
                <p className="text-sm text-gray-500">Paid At</p>
                <p className="text-sm">{formatDate(inv.paid_at)}</p>
              </div>
            )}
            <div>
              <p className="text-sm text-gray-500">Created</p>
              <p className="text-sm">{formatDate(inv.created_at)}</p>
            </div>
          </div>
        </div>

        {/* Customer & Links */}
        <div className="bg-white rounded-xl shadow-sm border p-6 space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">Customer & Links</h2>
          <div className="grid grid-cols-1 gap-4">
            <div>
              <p className="text-sm text-gray-500">Email</p>
              <button onClick={() => navigate(`/customers/${encodeURIComponent(inv.contact_email)}`)}
                className="text-sm text-indigo-600 hover:underline">{inv.contact_email}</button>
            </div>
            {inv.license_id && (
              <div>
                <p className="text-sm text-gray-500">License ID</p>
                <button onClick={() => navigate(`/licenses/${inv.license_id}`)}
                  className="text-xs font-mono text-indigo-600 hover:underline">{inv.license_id}</button>
              </div>
            )}
            <div>
              <p className="text-sm text-gray-500">Invoice ID (internal)</p>
              <p className="text-xs font-mono text-gray-600 break-all">{inv.id}</p>
            </div>
          </div>

          {/* External Links */}
          <div className="border-t pt-4 space-y-2">
            <h3 className="text-sm font-medium text-gray-700">External Links</h3>
            <div className="flex flex-wrap gap-2">
              {inv.invoice_pdf_url && (
                <a
                  href={inv.invoice_pdf_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-white bg-[#c8294f] rounded-md hover:bg-[#a82040]"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                  </svg>
                  Download PDF
                </a>
              )}
              {inv.hosted_invoice_url && (
                <a
                  href={inv.hosted_invoice_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-700 border border-gray-300 rounded-md hover:bg-gray-50"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                  </svg>
                  Hosted Invoice
                </a>
              )}
              {inv.stripe_invoice_id && (
                <a
                  href={`https://dashboard.stripe.com/invoices/${inv.stripe_invoice_id}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-indigo-700 border border-indigo-300 rounded-md hover:bg-indigo-50"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
                  </svg>
                  Stripe Dashboard
                </a>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
