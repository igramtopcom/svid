import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listAlertConfigs, createAlertConfig, updateAlertConfig, deleteAlertConfig, testAlert, listAlertLogs } from '@/api/alerts'
import { PageSkeleton } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import Pagination from '@/components/common/Pagination'
import { formatDate } from '@/lib/utils'
import { Bell, Plus, Trash2, Play, X } from 'lucide-react'

export default function AlertSettings() {
  const queryClient = useQueryClient()
  const [showForm, setShowForm] = useState(false)
  const [logPage, setLogPage] = useState(1)

  const { data: configs, isLoading } = useQuery({
    queryKey: ['alert-configs'],
    queryFn: listAlertConfigs,
  })

  const { data: logs } = useQuery({
    queryKey: ['alert-logs', logPage],
    queryFn: () => listAlertLogs({ page: logPage, per_page: 10 }),
  })

  const createMutation = useMutation({
    mutationFn: createAlertConfig,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['alert-configs'] })
      setShowForm(false)
      toast.success('Alert rule created')
    },
  })

  const toggleMutation = useMutation({
    mutationFn: ({ id, enabled }: { id: string; enabled: boolean }) =>
      updateAlertConfig(id, { is_enabled: enabled }),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['alert-configs'] }); toast.success('Alert updated') },
  })

  const deleteMutation = useMutation({
    mutationFn: deleteAlertConfig,
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['alert-configs'] }); toast.success('Alert deleted') },
  })

  const testMutation = useMutation({ mutationFn: testAlert, onSuccess: () => toast.success('Test alert sent') })

  const [form, setForm] = useState({
    name: '',
    metric_type: 'crash_rate',
    threshold: 10,
    window_mins: 60,
    channel: 'telegram',
    destination: '',
    cooldown_mins: 60,
  })

  const handleCreate = () => {
    createMutation.mutate(form)
  }

  if (isLoading) return <PageSkeleton cards={0} tableRows={4} />

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">Alert Settings</h2>
        <button
          onClick={() => setShowForm(!showForm)}
          className="flex items-center gap-2 px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700"
        >
          {showForm ? <X size={16} /> : <Plus size={16} />}
          {showForm ? 'Cancel' : 'New Alert Rule'}
        </button>
      </div>

      {/* Create Form */}
      {showForm && (
        <div className="bg-white rounded-lg border border-gray-200 p-6 mb-6">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">New Alert Rule</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Name</label>
              <input
                type="text"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                placeholder="e.g. Crash Spike Alert"
                className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Metric</label>
              <select
                value={form.metric_type}
                onChange={(e) => setForm({ ...form, metric_type: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
              >
                <option value="crash_rate">Crash Rate</option>
                <option value="error_rate">Error Events (analytics)</option>
                <option value="download_error_rate">Download Errors (structured)</option>
                <option value="new_bug_rate">New Bug Reports</option>
                <option value="crash_group_spike">Crash Group Spike</option>
                <option value="download_error_rate_pct">Download Error Rate %</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Threshold</label>
              <input
                type="number"
                value={form.threshold}
                onChange={(e) => setForm({ ...form, threshold: Number(e.target.value) })}
                min={1}
                className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Window (minutes)</label>
              <input
                type="number"
                value={form.window_mins}
                onChange={(e) => setForm({ ...form, window_mins: Number(e.target.value) })}
                min={5}
                max={1440}
                className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Channel</label>
              <select
                value={form.channel}
                onChange={(e) => setForm({ ...form, channel: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
              >
                <option value="telegram">Telegram</option>
                <option value="email">Email</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">
                {form.channel === 'telegram' ? 'Chat ID' : 'Email Address'}
              </label>
              <input
                type="text"
                value={form.destination}
                onChange={(e) => setForm({ ...form, destination: e.target.value })}
                placeholder={form.channel === 'telegram' ? '-100123456789' : 'admin@svid.app'}
                className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Cooldown (minutes)</label>
              <input
                type="number"
                value={form.cooldown_mins}
                onChange={(e) => setForm({ ...form, cooldown_mins: Number(e.target.value) })}
                min={5}
                className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
              />
            </div>
          </div>
          <button
            onClick={handleCreate}
            disabled={createMutation.isPending || !form.name || !form.destination}
            className="mt-4 px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50"
          >
            {createMutation.isPending ? 'Creating...' : 'Create Alert Rule'}
          </button>
        </div>
      )}

      {/* Alert Configs */}
      {!configs?.length ? (
        <EmptyState message="No alert rules configured" />
      ) : (
        <div className="space-y-3 mb-8">
          {configs.map((config) => (
            <div key={config.id} className="bg-white rounded-lg border border-gray-200 p-4 flex items-center justify-between">
              <div className="flex items-center gap-4">
                <Bell size={20} className={config.is_enabled ? 'text-brand-600' : 'text-gray-400'} />
                <div>
                  <h4 className="font-medium text-sm">{config.name}</h4>
                  <p className="text-xs text-gray-500">
                    {
                      { crash_rate: 'Crashes', error_rate: 'Error events', download_error_rate: 'Download errors', new_bug_rate: 'Bug reports', crash_group_spike: 'Grouped crashes', download_error_rate_pct: 'DL error rate %' }[config.metric_type] || config.metric_type
                    } {'>'} {config.threshold} in {config.window_mins}min
                    {' — '}{config.channel}: {config.destination}
                  </p>
                  {config.last_fired_at && (
                    <p className="text-xs text-orange-500 mt-0.5">Last fired: {formatDate(config.last_fired_at)}</p>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => testMutation.mutate(config.id)}
                  disabled={testMutation.isPending}
                  className="p-2 text-gray-500 hover:text-brand-600"
                  title="Send test notification"
                >
                  <Play size={16} />
                </button>
                <button
                  onClick={() => toggleMutation.mutate({ id: config.id, enabled: !config.is_enabled })}
                  className={`px-3 py-1 rounded-full text-xs font-medium ${
                    config.is_enabled ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'
                  }`}
                >
                  {config.is_enabled ? 'Enabled' : 'Disabled'}
                </button>
                <button
                  onClick={() => {
                    if (confirm('Delete this alert rule?')) deleteMutation.mutate(config.id)
                  }}
                  className="p-2 text-gray-400 hover:text-red-600"
                >
                  <Trash2 size={16} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Alert Logs */}
      <h3 className="text-lg font-semibold mb-3">Alert History</h3>
      {!logs?.items?.length ? (
        <EmptyState message="No alerts sent yet" />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Message</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Channel</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Value</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {logs.items.map((log) => (
                  <tr key={log.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3 text-gray-700 max-w-xs truncate">{log.message}</td>
                    <td className="px-4 py-3 text-gray-600 capitalize">{log.channel}</td>
                    <td className="px-4 py-3 font-mono">{log.metric_value}</td>
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        log.status === 'sent' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
                      }`}>
                        {log.status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(log.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={logPage} totalPages={logs.total_pages} total={logs.total} onPageChange={setLogPage} />
        </>
      )}
    </div>
  )
}
