import { useState } from 'react'
import { useParams, Link, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getDevice, updateDevice, getDeviceTimeline } from '@/api/devices'
import { listBugs } from '@/api/bugs'
import { listCrashes } from '@/api/bugs'
import { listTickets } from '@/api/feedback'
import { listApiKeys, revokeApiKey } from '@/api/system'
import StatusBadge from '@/components/common/StatusBadge'
import LoadingSpinner from '@/components/common/LoadingSpinner'
import { formatDate, truncate } from '@/lib/utils'
import { ArrowLeft, Bug, AlertTriangle, MessageSquare, Clock, KeyRound } from 'lucide-react'

export default function DeviceDetail() {
  const { id } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const [tab, setTab] = useState<'timeline' | 'bugs' | 'crashes' | 'tickets' | 'keys'>('timeline')
  const [timelinePage, setTimelinePage] = useState(1)

  const { data: device, isLoading } = useQuery({
    queryKey: ['device', id],
    queryFn: () => getDevice(id!),
  })

  const { data: timelineData, isLoading: timelineLoading } = useQuery({
    queryKey: ['device-timeline', id, timelinePage],
    queryFn: () => getDeviceTimeline(id!, { page: timelinePage, per_page: 30 }),
    enabled: tab === 'timeline',
  })

  const { data: bugsData } = useQuery({
    queryKey: ['device-bugs', id],
    queryFn: () => listBugs({ page: 1, per_page: 50, device_id: id }),
    enabled: tab === 'bugs',
  })

  const { data: crashesData } = useQuery({
    queryKey: ['device-crashes', id],
    queryFn: () => listCrashes({ page: 1, per_page: 50, device_id: id }),
    enabled: tab === 'crashes',
  })

  const { data: ticketsData } = useQuery({
    queryKey: ['device-tickets', id],
    queryFn: () => listTickets({ page: 1, per_page: 50, device_id: id }),
    enabled: tab === 'tickets',
  })

  const { data: apiKeys, refetch: refetchKeys } = useQuery({
    queryKey: ['device-api-keys', id],
    queryFn: () => listApiKeys(id!),
    enabled: tab === 'keys',
  })

  const mutation = useMutation({
    mutationFn: (data: { tier?: string; is_active?: boolean }) => updateDevice(id!, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['device', id] })
      toast.success('Device updated')
    },
  })

  if (isLoading) return <LoadingSpinner />
  if (!device) return <p className="text-gray-500">Device not found</p>

  const tabs = [
    { key: 'timeline' as const, label: 'Timeline', icon: <Clock size={14} /> },
    { key: 'bugs' as const, label: 'Bugs', icon: <Bug size={14} /> },
    { key: 'crashes' as const, label: 'Crashes', icon: <AlertTriangle size={14} /> },
    { key: 'tickets' as const, label: 'Tickets', icon: <MessageSquare size={14} /> },
    { key: 'keys' as const, label: 'API Keys', icon: <KeyRound size={14} /> },
  ]

  return (
    <div>
      <Link to="/devices" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
        <ArrowLeft size={16} /> Back to Devices
      </Link>

      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-4">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="text-xl font-bold">{device.device_name || device.hardware_id}</h2>
            <p className="text-sm text-gray-500 mt-1">{device.hardware_id}</p>
          </div>
          <StatusBadge status={device.is_active ? 'active' : 'inactive'} />
        </div>

        <div className="grid grid-cols-2 lg:grid-cols-3 gap-6">
          <InfoRow label="OS" value={`${device.os} ${device.os_version}`} />
          <InfoRow label="App Version" value={device.app_version} />
          <InfoRow label="Tier" value={device.tier} />
          <InfoRow label="Registered" value={formatDate(device.created_at)} />
          <InfoRow label="Last Seen" value={formatDate(device.last_seen_at)} />
          <InfoRow label="ID" value={device.id} />
        </div>

        <div className="mt-6 pt-6 border-t flex gap-3">
          <select
            value={device.tier}
            onChange={(e) => mutation.mutate({ tier: e.target.value })}
            className="px-3 py-2 border border-gray-300 rounded-md text-sm"
          >
            <option value="free">Free</option>
            <option value="pro">Pro</option>
            <option value="enterprise">Enterprise</option>
          </select>

          <button
            onClick={() => mutation.mutate({ is_active: !device.is_active })}
            className={`px-4 py-2 rounded-md text-sm font-medium ${
              device.is_active
                ? 'bg-red-50 text-red-600 hover:bg-red-100'
                : 'bg-green-50 text-green-600 hover:bg-green-100'
            }`}
          >
            {device.is_active ? 'Deactivate' : 'Activate'}
          </button>
        </div>
      </div>

      {/* Activity Tabs */}
      <div className="bg-white rounded-lg border border-gray-200">
        <div className="border-b flex">
          {tabs.map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`px-4 py-3 text-sm font-medium flex items-center gap-1.5 border-b-2 ${
                tab === t.key
                  ? 'border-brand-600 text-brand-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              {t.icon} {t.label}
            </button>
          ))}
        </div>

        <div className="p-4">
          {tab === 'timeline' && (
            timelineLoading ? <LoadingSpinner /> :
            timelineData?.events?.length ? (
              <div>
                <div className="space-y-3">
                  {timelineData.events.map((ev, i) => (
                    <div key={i} className="flex gap-3 items-start">
                      <div className={`mt-1 w-2.5 h-2.5 rounded-full flex-shrink-0 ${
                        ev.severity === 'critical' ? 'bg-red-600' :
                        ev.severity === 'high' ? 'bg-orange-500' :
                        ev.severity === 'medium' ? 'bg-yellow-500' :
                        ev.severity === 'low' ? 'bg-blue-400' :
                        'bg-gray-400'
                      }`} />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <StatusBadge status={ev.type} />
                          <span className="text-xs text-gray-400">{formatDate(ev.timestamp)}</span>
                        </div>
                        <p
                          className="text-sm font-medium mt-0.5 text-indigo-600 hover:underline cursor-pointer"
                          onClick={() => {
                            const routes: Record<string, string> = {
                              crash: `/crashes/${ev.related_id}`,
                              bug_report: `/bugs/${ev.related_id}`,
                              ticket: `/tickets/${ev.related_id}`,
                              license: `/licenses/${ev.related_id}`,
                              download_error: `/download-errors`,
                            }
                            const route = routes[ev.type]
                            if (route) navigate(route)
                          }}
                        >
                          {truncate(ev.title, 80)}
                        </p>
                        {ev.metadata && <p className="text-xs text-gray-400 mt-0.5">{ev.metadata}</p>}
                      </div>
                    </div>
                  ))}
                </div>
                {timelineData.total_count > 30 && (
                  <div className="mt-4 flex justify-center gap-2">
                    <button
                      onClick={() => setTimelinePage(p => Math.max(1, p - 1))}
                      disabled={timelinePage === 1}
                      className="px-3 py-1 text-sm border rounded disabled:opacity-50"
                    >
                      Previous
                    </button>
                    <span className="px-3 py-1 text-sm text-gray-500">
                      Page {timelinePage} of {Math.ceil(timelineData.total_count / 30)}
                    </span>
                    <button
                      onClick={() => setTimelinePage(p => p + 1)}
                      disabled={timelinePage >= Math.ceil(timelineData.total_count / 30)}
                      className="px-3 py-1 text-sm border rounded disabled:opacity-50"
                    >
                      Next
                    </button>
                  </div>
                )}
              </div>
            ) : <p className="text-sm text-gray-500">No timeline events for this device.</p>
          )}

          {tab === 'bugs' && (
            bugsData?.items?.length ? (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-2 text-gray-500 font-medium">Title</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Status</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Priority</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Date</th>
                  </tr>
                </thead>
                <tbody>
                  {bugsData.items.map((b) => (
                    <tr key={b.id} className="border-b last:border-0 hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/bugs/${b.id}`)}>
                      <td className="py-2 text-indigo-600">{truncate(b.title, 50)}</td>
                      <td className="py-2"><StatusBadge status={b.status} /></td>
                      <td className="py-2"><StatusBadge status={b.priority} /></td>
                      <td className="py-2 text-gray-500">{formatDate(b.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : <p className="text-sm text-gray-500">No bug reports from this device.</p>
          )}

          {tab === 'crashes' && (
            crashesData?.items?.length ? (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-2 text-gray-500 font-medium">Severity</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Message</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Date</th>
                  </tr>
                </thead>
                <tbody>
                  {crashesData.items.map((c) => (
                    <tr key={c.id} className="border-b last:border-0 hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/crashes/${c.id}`)}>
                      <td className="py-2"><StatusBadge status={c.severity || 'medium'} /></td>
                      <td className="py-2 text-indigo-600">{truncate(c.error_message, 60)}</td>
                      <td className="py-2 text-gray-500">{formatDate(c.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : <p className="text-sm text-gray-500">No crash reports from this device.</p>
          )}

          {tab === 'tickets' && (
            ticketsData?.items?.length ? (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-2 text-gray-500 font-medium">Subject</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Status</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Date</th>
                  </tr>
                </thead>
                <tbody>
                  {ticketsData.items.map((t) => (
                    <tr key={t.id} className="border-b last:border-0 hover:bg-gray-50 cursor-pointer" onClick={() => navigate(`/tickets/${t.id}`)}>
                      <td className="py-2 text-indigo-600">{truncate(t.subject, 50)}</td>
                      <td className="py-2"><StatusBadge status={t.status} /></td>
                      <td className="py-2 text-gray-500">{formatDate(t.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : <p className="text-sm text-gray-500">No tickets from this device.</p>
          )}

          {tab === 'keys' && (
            apiKeys?.length ? (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b">
                    <th className="text-left py-2 text-gray-500 font-medium">Key ID</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Status</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Created</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Expires</th>
                    <th className="text-left py-2 text-gray-500 font-medium">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {apiKeys.map((k) => (
                    <tr key={k.id} className="border-b last:border-0">
                      <td className="py-2 font-mono text-xs">{k.id.slice(0, 12)}...</td>
                      <td className="py-2">
                        {k.is_revoked ? (
                          <span className="text-xs px-2 py-0.5 bg-red-100 text-red-700 rounded">Revoked</span>
                        ) : k.is_valid ? (
                          <span className="text-xs px-2 py-0.5 bg-green-100 text-green-700 rounded">Active</span>
                        ) : (
                          <span className="text-xs px-2 py-0.5 bg-yellow-100 text-yellow-700 rounded">Expired</span>
                        )}
                      </td>
                      <td className="py-2 text-gray-500">{formatDate(k.created_at)}</td>
                      <td className="py-2 text-gray-500">{formatDate(k.expires_at)}</td>
                      <td className="py-2">
                        {!k.is_revoked && (
                          <button
                            onClick={async () => {
                              if (confirm('Revoke this API key? The device will need to re-register.')) {
                                await revokeApiKey(k.id)
                                refetchKeys()
                              }
                            }}
                            className="text-xs text-red-600 hover:underline"
                          >
                            Revoke
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : <p className="text-sm text-gray-500">No API keys for this device.</p>
          )}
        </div>
      </div>
    </div>
  )
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs text-gray-500 mb-1">{label}</p>
      <p className="text-sm font-medium">{value || '-'}</p>
    </div>
  )
}
