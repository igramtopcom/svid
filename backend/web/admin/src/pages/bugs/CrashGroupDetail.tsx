import { useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getCrashGroup, updateCrashGroup, listGroupCrashes, listCrashGroups, mergeCrashGroups } from '@/api/bugs'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import LoadingSpinner from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import { formatDate, truncate } from '@/lib/utils'

const STATUSES = ['new', 'investigating', 'fixing', 'resolved', 'wont_fix']
const SEVERITIES = ['critical', 'high', 'medium', 'low']

export default function CrashGroupDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [crashPage, setCrashPage] = useState(1)
  const [notes, setNotes] = useState('')
  const [notesLoaded, setNotesLoaded] = useState(false)
  const [showMerge, setShowMerge] = useState(false)
  const [selectedSources, setSelectedSources] = useState<string[]>([])

  const { data: group, isLoading } = useQuery({
    queryKey: ['crash-group', id],
    queryFn: () => getCrashGroup(id!),
    enabled: !!id,
  })

  // Load notes from group data once
  if (group && !notesLoaded) {
    setNotes(group.admin_notes || '')
    setNotesLoaded(true)
  }

  const { data: crashes, isLoading: crashesLoading } = useQuery({
    queryKey: ['crash-group-crashes', id, crashPage],
    queryFn: () => listGroupCrashes(id!, { page: crashPage, per_page: 20 }),
    enabled: !!id,
  })

  const updateMutation = useMutation({
    mutationFn: (data: { status?: string; severity?: string; admin_notes?: string; assigned_to?: string }) =>
      updateCrashGroup(id!, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['crash-group', id] })
      queryClient.invalidateQueries({ queryKey: ['crash-group-stats'] })
      toast.success('Crash group updated')
    },
  })

  // Other groups for merge (exclude current)
  const { data: otherGroups } = useQuery({
    queryKey: ['crash-groups-for-merge'],
    queryFn: () => listCrashGroups({ page: 1, per_page: 100 }),
    enabled: showMerge,
  })

  const mergeMutation = useMutation({
    mutationFn: () => mergeCrashGroups(id!, selectedSources),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['crash-group', id] })
      queryClient.invalidateQueries({ queryKey: ['crash-groups'] })
      queryClient.invalidateQueries({ queryKey: ['crash-group-stats'] })
      setShowMerge(false)
      setSelectedSources([])
      toast.success('Crash groups merged')
    },
  })

  const toggleSource = (sourceId: string) => {
    setSelectedSources((prev) =>
      prev.includes(sourceId) ? prev.filter((s) => s !== sourceId) : [...prev, sourceId]
    )
  }

  if (isLoading) return <LoadingSpinner />
  if (!group) return <EmptyState message="Crash group not found" />

  return (
    <div>
      <button onClick={() => navigate('/crash-groups')} className="text-sm text-gray-500 hover:text-gray-700 mb-4 inline-block">
        &larr; Back to Crash Groups
      </button>

      <div className="grid grid-cols-3 gap-6">
        {/* Main Info */}
        <div className="col-span-2 space-y-6">
          <div className="bg-white rounded-lg border border-gray-200 p-6">
            <div className="flex items-start justify-between mb-4">
              <div>
                <h2 className="text-xl font-bold mb-2">{group.title}</h2>
                <div className="flex gap-2">
                  <StatusBadge status={group.severity} />
                  <StatusBadge status={group.status} />
                </div>
              </div>
              <div className="text-right text-sm text-gray-500">
                <p>Crashes: <span className="font-bold text-gray-800">{group.crash_count}</span></p>
                <p>Devices: <span className="font-bold text-gray-800">{group.device_count}</span></p>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <p className="text-gray-500">Fingerprint</p>
                <p className="font-mono text-xs break-all">{group.fingerprint}</p>
              </div>
              <div>
                <p className="text-gray-500">Platforms</p>
                <p>{group.platforms || 'N/A'}</p>
              </div>
              <div>
                <p className="text-gray-500">Versions</p>
                <p>{group.versions || 'N/A'}</p>
              </div>
              <div>
                <p className="text-gray-500">First Seen</p>
                <p>{formatDate(group.first_seen_at)}</p>
              </div>
              <div>
                <p className="text-gray-500">Last Seen</p>
                <p>{formatDate(group.last_seen_at)}</p>
              </div>
              {group.assigned_to && (
                <div>
                  <p className="text-gray-500">Assigned To</p>
                  <p>{group.assigned_to}</p>
                </div>
              )}
            </div>
          </div>

          {/* Crashes in this group */}
          <div className="bg-white rounded-lg border border-gray-200 p-6">
            <h3 className="text-lg font-bold mb-4">Crashes ({group.crash_count})</h3>
            {crashesLoading ? (
              <LoadingSpinner />
            ) : !crashes?.items?.length ? (
              <EmptyState message="No crashes in this group" />
            ) : (
              <>
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b">
                      <th className="text-left px-3 py-2 font-medium text-gray-600">Severity</th>
                      <th className="text-left px-3 py-2 font-medium text-gray-600">Message</th>
                      <th className="text-left px-3 py-2 font-medium text-gray-600">OS</th>
                      <th className="text-left px-3 py-2 font-medium text-gray-600">Version</th>
                      <th className="text-left px-3 py-2 font-medium text-gray-600">Date</th>
                    </tr>
                  </thead>
                  <tbody>
                    {crashes.items.map((crash) => (
                      <tr
                        key={crash.id}
                        className="border-b last:border-0 hover:bg-gray-50 cursor-pointer"
                        onClick={() => navigate(`/crashes/${crash.id}`)}
                      >
                        <td className="px-3 py-2"><StatusBadge status={crash.severity || 'medium'} /></td>
                        <td className="px-3 py-2 text-indigo-600">{truncate(crash.error_message, 50)}</td>
                        <td className="px-3 py-2 text-gray-600">{crash.os}</td>
                        <td className="px-3 py-2 text-gray-600">{crash.app_version}</td>
                        <td className="px-3 py-2 text-gray-500">{formatDate(crash.created_at)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <Pagination page={crashPage} totalPages={crashes.total_pages} total={crashes.total} onPageChange={setCrashPage} />
              </>
            )}
          </div>
        </div>

        {/* Sidebar: Admin Actions */}
        <div className="space-y-4">
          <div className="bg-white rounded-lg border border-gray-200 p-4">
            <h3 className="font-bold mb-3">Actions</h3>

            <label className="block text-sm text-gray-600 mb-1">Status</label>
            <select
              value={group.status}
              onChange={(e) => updateMutation.mutate({ status: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm mb-3"
            >
              {STATUSES.map((s) => (
                <option key={s} value={s}>{s.replace('_', ' ')}</option>
              ))}
            </select>

            <label className="block text-sm text-gray-600 mb-1">Severity</label>
            <select
              value={group.severity}
              onChange={(e) => updateMutation.mutate({ severity: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm mb-3"
            >
              {SEVERITIES.map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>

            <label className="block text-sm text-gray-600 mb-1">Admin Notes</label>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={4}
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm mb-2"
            />
            <button
              onClick={() => updateMutation.mutate({ admin_notes: notes })}
              disabled={updateMutation.isPending}
              className="w-full px-3 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50"
            >
              {updateMutation.isPending ? 'Saving...' : 'Save Notes'}
            </button>
          </div>

          {/* Merge */}
          <div className="bg-white rounded-lg border border-gray-200 p-4">
            <h3 className="font-bold mb-2">Merge Groups</h3>
            <p className="text-xs text-gray-500 mb-3">Merge other crash groups into this one. Source groups will be deleted and their crashes reassigned here.</p>
            <button
              onClick={() => setShowMerge(true)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm hover:bg-gray-50"
            >
              Select Groups to Merge
            </button>
          </div>
        </div>
      </div>

      {/* Merge Modal */}
      {showMerge && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <div className="bg-white rounded-xl shadow-xl w-[600px] max-h-[70vh] flex flex-col">
            <div className="p-5 border-b">
              <h2 className="text-lg font-bold">Merge Crash Groups</h2>
              <p className="text-sm text-gray-500 mt-1">
                Select groups to merge <strong>into</strong> this group ({truncate(group.title, 40)}).
                Source groups will be deleted.
              </p>
            </div>
            <div className="flex-1 overflow-y-auto p-5">
              {!otherGroups?.items?.length ? (
                <p className="text-sm text-gray-400">No other groups available</p>
              ) : (
                <div className="space-y-2">
                  {otherGroups.items
                    .filter((g) => g.id !== id)
                    .map((g) => (
                      <label key={g.id} className="flex items-start gap-3 p-3 rounded-lg border hover:bg-gray-50 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={selectedSources.includes(g.id)}
                          onChange={() => toggleSource(g.id)}
                          className="mt-1"
                        />
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium truncate">{g.title}</p>
                          <div className="flex gap-2 mt-1">
                            <StatusBadge status={g.severity} />
                            <StatusBadge status={g.status} />
                            <span className="text-xs text-gray-400">{g.crash_count} crashes · {g.device_count} devices</span>
                          </div>
                        </div>
                      </label>
                    ))}
                </div>
              )}
            </div>
            <div className="p-4 border-t flex justify-between items-center">
              <span className="text-sm text-gray-500">{selectedSources.length} group(s) selected</span>
              <div className="flex gap-2">
                <button
                  onClick={() => { setShowMerge(false); setSelectedSources([]) }}
                  className="px-4 py-2 text-sm text-gray-600 hover:text-gray-800"
                >
                  Cancel
                </button>
                <button
                  onClick={() => {
                    if (selectedSources.length > 0 && confirm(`Merge ${selectedSources.length} group(s) into this one? This cannot be undone.`)) {
                      mergeMutation.mutate()
                    }
                  }}
                  disabled={selectedSources.length === 0 || mergeMutation.isPending}
                  className="px-4 py-2 bg-red-600 text-white rounded-lg text-sm hover:bg-red-700 disabled:opacity-50"
                >
                  {mergeMutation.isPending ? 'Merging...' : `Merge ${selectedSources.length} Group(s)`}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
