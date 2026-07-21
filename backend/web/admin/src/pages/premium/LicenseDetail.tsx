import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { getLicense, updateLicense, listTransactions, refundTransaction, listLicenseDevices, removeLicenseDevice } from '@/api/premium'
import type { LicenseDevice } from '@/api/premium'
import { useState } from 'react'
import type { License, Transaction } from '@/types'
import StatusBadge from '@/components/common/StatusBadge'
import { formatDate, formatCents } from '@/lib/utils'

function TierBadge({ tier }: { tier: string }) {
  return (
    <span className={`px-2 py-1 rounded-full text-xs font-medium ${
      tier === 'premium' ? 'bg-purple-100 text-purple-800' : 'bg-gray-100 text-gray-600'
    }`}>
      {tier}
    </span>
  )
}

export default function LicenseDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [editing, setEditing] = useState(false)
  const [editForm, setEditForm] = useState<{
    tier?: string
    is_auto_renew?: boolean
    expires_at?: string
  }>({})

  const { data: license, isLoading, error } = useQuery({
    queryKey: ['license', id],
    queryFn: () => getLicense(id!),
    enabled: !!id,
  })

  const { data: txnData } = useQuery({
    queryKey: ['license-transactions', id],
    queryFn: () => listTransactions({ per_page: 50, search: license?.contact_email || license?.device_id || '' }),
    enabled: !!id && !!license,
  })

  const updateMutation = useMutation({
    mutationFn: (data: Partial<License>) => updateLicense(id!, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['license', id] })
      setEditing(false)
    },
  })

  const { data: devices } = useQuery({
    queryKey: ['license-devices', id],
    queryFn: () => listLicenseDevices(id!),
    enabled: !!id,
  })

  const refundMutation = useMutation({
    mutationFn: ({ txnId, cancelLicense }: { txnId: string; cancelLicense: boolean }) =>
      refundTransaction(txnId, cancelLicense),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['license-transactions', id] })
      queryClient.invalidateQueries({ queryKey: ['license', id] })
    },
  })

  const removeDeviceMutation = useMutation({
    mutationFn: (deviceId: string) => removeLicenseDevice(id!, deviceId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['license-devices', id] })
    },
  })

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-indigo-600" />
      </div>
    )
  }

  if (error || !license) {
    return (
      <div className="text-center py-12">
        <p className="text-red-600">Failed to load license</p>
        <button onClick={() => navigate('/premium')} className="mt-4 text-indigo-600 hover:underline">
          Back to Premium
        </button>
      </div>
    )
  }

  const transactions = txnData?.items || []

  const maxDevices = (() => {
    switch (license.billing_cycle) {
      case 'monthly': return 5
      case 'yearly': return 10
      case 'lifetime1': return 1
      case 'lifetime2': return 3
      case 'lifetime3': return 10
      default: return 5
    }
  })()

  const isExpired = new Date(license.expires_at) < new Date()
  const daysUntilExpiry = Math.ceil(
    (new Date(license.expires_at).getTime() - Date.now()) / (1000 * 60 * 60 * 24)
  )

  const handleSave = () => {
    const updates: Partial<License> = {}
    if (editForm.tier !== undefined) updates.tier = editForm.tier
    if (editForm.is_auto_renew !== undefined) updates.is_auto_renew = editForm.is_auto_renew
    if (editForm.expires_at !== undefined) updates.expires_at = editForm.expires_at
    updateMutation.mutate(updates)
  }

  const handleStartEdit = () => {
    setEditForm({
      tier: license.tier,
      is_auto_renew: license.is_auto_renew,
      expires_at: license.expires_at.split('T')[0] + 'T' + license.expires_at.split('T')[1]?.substring(0, 5),
    })
    setEditing(true)
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button onClick={() => navigate('/premium')} className="text-gray-400 hover:text-gray-600">
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">License Details</h1>
            <p className="text-sm text-gray-500 font-mono">{license.license_key}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {!editing ? (
            <button
              onClick={handleStartEdit}
              className="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 text-sm"
            >
              Edit License
            </button>
          ) : (
            <>
              <button
                onClick={() => setEditing(false)}
                className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 text-sm"
              >
                Cancel
              </button>
              <button
                onClick={handleSave}
                disabled={updateMutation.isPending}
                className="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 text-sm disabled:opacity-50"
              >
                {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
              </button>
            </>
          )}
        </div>
      </div>

      {/* Main Info Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* License Info Card */}
        <div className="bg-white rounded-xl shadow-sm border p-6 space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">License Information</h2>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-sm text-gray-500">License Key</p>
              <p className="font-mono text-sm">{license.license_key}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Tier</p>
              {editing ? (
                <select
                  value={editForm.tier}
                  onChange={(e) => setEditForm({ ...editForm, tier: e.target.value })}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm text-sm"
                >
                  <option value="free">Free</option>
                  <option value="premium">Premium</option>
                </select>
              ) : (
                <TierBadge tier={license.tier} />
              )}
            </div>
            <div>
              <p className="text-sm text-gray-500">Billing Cycle</p>
              <p className="text-sm capitalize">{license.billing_cycle}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Payment Method</p>
              <p className="text-sm capitalize">{license.payment_method}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Auto-Renew</p>
              {editing ? (
                <label className="flex items-center gap-2 mt-1">
                  <input
                    type="checkbox"
                    checked={editForm.is_auto_renew}
                    onChange={(e) => setEditForm({ ...editForm, is_auto_renew: e.target.checked })}
                    className="rounded border-gray-300"
                  />
                  <span className="text-sm">{editForm.is_auto_renew ? 'Yes' : 'No'}</span>
                </label>
              ) : (
                <p className="text-sm">{license.is_auto_renew ? 'Yes' : 'No'}</p>
              )}
            </div>
            <div>
              <p className="text-sm text-gray-500">Expires</p>
              {editing ? (
                <input
                  type="datetime-local"
                  value={editForm.expires_at?.substring(0, 16)}
                  onChange={(e) => setEditForm({ ...editForm, expires_at: e.target.value + ':00Z' })}
                  className="mt-1 block w-full rounded-md border-gray-300 shadow-sm text-sm"
                />
              ) : (
                <div>
                  <p className="text-sm">{formatDate(license.expires_at)}</p>
                  <p className={`text-xs ${isExpired ? 'text-red-600' : daysUntilExpiry <= 7 ? 'text-orange-600' : 'text-green-600'}`}>
                    {isExpired ? 'Expired' : `${daysUntilExpiry} days remaining`}
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Device & Stripe Info Card */}
        <div className="bg-white rounded-xl shadow-sm border p-6 space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">Device & Payment</h2>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-sm text-gray-500">Device ID</p>
              <p className="font-mono text-xs break-all">{license.device_id}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Created</p>
              <p className="text-sm">{formatDate(license.created_at)}</p>
            </div>
            {license.stripe_customer_id && (
              <div>
                <p className="text-sm text-gray-500">Stripe Customer</p>
                <p className="font-mono text-xs">{license.stripe_customer_id}</p>
              </div>
            )}
            {license.stripe_subscription_id && (
              <div>
                <p className="text-sm text-gray-500">Stripe Subscription</p>
                <p className="font-mono text-xs">{license.stripe_subscription_id}</p>
              </div>
            )}
            {license.cancelled_at && (
              <div className="col-span-2">
                <p className="text-sm text-gray-500">Cancelled At</p>
                <p className="text-sm text-red-600">{formatDate(license.cancelled_at)}</p>
              </div>
            )}
            <div>
              <p className="text-sm text-gray-500">Last Updated</p>
              <p className="text-sm">{formatDate(license.updated_at)}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Transaction History */}
      <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
        <div className="px-6 py-4 border-b">
          <h2 className="text-lg font-semibold text-gray-900">Payment History</h2>
        </div>

        {transactions.length === 0 ? (
          <div className="px-6 py-8 text-center text-gray-500">
            No transactions found for this device
          </div>
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
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {transactions.map((txn: Transaction) => (
                  <tr key={txn.id} className="hover:bg-gray-50">
                    <td className="px-6 py-3 text-xs font-mono text-gray-500">{txn.id.substring(0, 8)}...</td>
                    <td className="px-6 py-3 text-sm capitalize">{txn.payment_method}</td>
                    <td className="px-6 py-3 text-sm capitalize">{txn.billing_cycle}</td>
                    <td className="px-6 py-3 text-sm font-medium">{formatCents(txn.amount_cents)}</td>
                    <td className="px-6 py-3"><StatusBadge status={txn.status} /></td>
                    <td className="px-6 py-3 text-sm text-gray-500">{formatDate(txn.created_at)}</td>
                    <td className="px-6 py-3">
                      {txn.status === 'completed' && (
                        <button
                          onClick={() => {
                            if (!confirm('Refund this transaction?')) return
                            const cancelLicense = confirm('Also cancel the associated license?')
                            refundMutation.mutate({ txnId: txn.id, cancelLicense })
                          }}
                          disabled={refundMutation.isPending}
                          className="text-xs px-2 py-1 bg-red-50 text-red-700 rounded hover:bg-red-100 disabled:opacity-50"
                        >
                          Refund
                        </button>
                      )}
                      {txn.status === 'refunded' && (
                        <span className="text-xs text-gray-400">Refunded</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Registered Devices */}
      <div className="bg-white rounded-xl shadow-sm border overflow-hidden">
        <div className="px-6 py-4 border-b flex items-center justify-between">
          <h2 className="text-lg font-semibold text-gray-900">Registered Devices</h2>
          <span className="text-sm text-gray-500">{devices?.length || 0} / {maxDevices} slots used</span>
        </div>

        {!devices?.length ? (
          <div className="px-6 py-8 text-center text-gray-500">No devices registered</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Device ID</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Registered</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Last Verified</th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {devices.map((device: LicenseDevice) => (
                  <tr key={device.id} className="hover:bg-gray-50">
                    <td className="px-6 py-3 font-mono text-xs text-gray-700">{device.device_id}</td>
                    <td className="px-6 py-3 text-sm text-gray-500">{formatDate(device.registered_at)}</td>
                    <td className="px-6 py-3 text-sm text-gray-500">{formatDate(device.last_verified_at)}</td>
                    <td className="px-6 py-3">
                      <button
                        onClick={() => {
                          if (confirm(`Remove device ${device.device_id.substring(0, 8)}... from this license?`)) {
                            removeDeviceMutation.mutate(device.device_id)
                          }
                        }}
                        disabled={removeDeviceMutation.isPending}
                        className="text-xs px-2 py-1 bg-red-50 text-red-700 rounded hover:bg-red-100 disabled:opacity-50"
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Danger Zone */}
      {!license.cancelled_at && license.tier === 'premium' && (
        <div className="bg-red-50 rounded-xl border border-red-200 p-6">
          <h3 className="text-lg font-semibold text-red-900">Danger Zone</h3>
          <p className="text-sm text-red-700 mt-1">Revoking a license will downgrade the user to free tier.</p>
          <button
            onClick={() => {
              if (confirm('Are you sure you want to revoke this license?')) {
                updateMutation.mutate({ tier: 'free', is_auto_renew: false, cancelled_at: new Date().toISOString() })
              }
            }}
            className="mt-3 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 text-sm"
          >
            Revoke License
          </button>
        </div>
      )}
    </div>
  )
}
