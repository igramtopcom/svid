import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { getCrash, getCrashLog, updateCrash } from '@/api/bugs'
import StatusBadge from '@/components/common/StatusBadge'
import LoadingSpinner from '@/components/common/LoadingSpinner'
import { formatDate } from '@/lib/utils'
import { ArrowLeft, FileText } from 'lucide-react'

export default function CrashDetail() {
  const { id } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const [showLog, setShowLog] = useState(false)
  const [notes, setNotes] = useState('')
  const [notesLoaded, setNotesLoaded] = useState(false)

  const { data: crash, isLoading } = useQuery({
    queryKey: ['crash', id],
    queryFn: () => getCrash(id!),
  })

  if (crash && !notesLoaded) {
    setNotes(crash.admin_notes || '')
    setNotesLoaded(true)
  }

  const { data: diagLog, isLoading: logLoading } = useQuery({
    queryKey: ['crash-log', id],
    queryFn: () => getCrashLog(id!),
    enabled: showLog && !!crash?.has_diagnostics,
    retry: false,
  })

  const updateMutation = useMutation({
    mutationFn: (data: { admin_notes?: string }) => updateCrash(id!, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['crash', id] })
    },
  })

  if (isLoading) return <LoadingSpinner />
  if (!crash) return <p className="text-gray-500">Crash report not found</p>

  return (
    <div>
      <Link to="/crashes" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
        <ArrowLeft size={16} /> Back to Crashes
      </Link>

      <div className="grid grid-cols-3 gap-6">
        <div className="col-span-2 space-y-4">
          <div className="bg-white rounded-lg border border-gray-200 p-6">
            <div className="flex items-start justify-between mb-4">
              <h2 className="text-xl font-bold">Crash Report</h2>
              <StatusBadge status={crash.severity || 'medium'} />
            </div>

            <div className="mb-4">
              <label className="text-xs text-gray-500 uppercase tracking-wide">Error Message</label>
              <p className="text-sm text-gray-800 mt-1">{crash.error_message}</p>
            </div>

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4 text-sm">
              <div><span className="text-gray-500">OS:</span> {crash.os} {crash.os_version}</div>
              <div><span className="text-gray-500">Version:</span> {crash.app_version}</div>
              <div>
                <span className="text-gray-500">Device:</span>{' '}
                <Link to={`/devices/${crash.device_id}`} className="font-mono text-xs text-indigo-600 hover:underline">
                  {crash.device_id.slice(0, 8)}...
                </Link>
              </div>
              <div><span className="text-gray-500">Date:</span> {formatDate(crash.created_at)}</div>
            </div>

            {crash.crash_group_id && (
              <div className="mb-4">
                <Link
                  to={`/crash-groups/${crash.crash_group_id}`}
                  className="inline-flex items-center gap-1 text-sm text-brand-600 hover:text-brand-700"
                >
                  View Crash Group &rarr;
                </Link>
              </div>
            )}

            {crash.metadata && (
              <div className="mb-4">
                <label className="text-xs text-gray-500 uppercase tracking-wide">Metadata</label>
                <pre className="text-xs bg-gray-50 text-gray-700 p-3 rounded mt-1 overflow-x-auto">{crash.metadata}</pre>
              </div>
            )}
          </div>

          {/* Diagnostic Log */}
          {crash.has_diagnostics && (
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-gray-700 flex items-center gap-2">
                  <FileText size={16} /> Diagnostic Log
                </h3>
                <button
                  onClick={() => setShowLog(!showLog)}
                  className="text-sm text-brand-600 hover:text-brand-700"
                >
                  {showLog ? 'Hide' : 'Show'} Log
                </button>
              </div>
              {showLog && (
                logLoading ? <LoadingSpinner /> : diagLog ? (
                  <div>
                    <p className="text-xs text-gray-500 mb-2">{diagLog.line_count} lines, {(diagLog.size_bytes / 1024).toFixed(1)} KB</p>
                    <pre className="text-xs bg-gray-900 text-green-400 p-4 rounded overflow-x-auto max-h-96 whitespace-pre-wrap">
                      {diagLog.content}
                    </pre>
                  </div>
                ) : <p className="text-xs text-gray-500">Log not available</p>
              )}
            </div>
          )}

          {crash.stack_trace && (
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-semibold text-gray-700 mb-3">Stack Trace</h3>
              <pre className="text-xs bg-gray-900 text-green-400 p-4 rounded overflow-x-auto max-h-96 whitespace-pre-wrap">
                {crash.stack_trace}
              </pre>
            </div>
          )}
        </div>

        {/* Sidebar: Admin Notes */}
        <div>
          <div className="bg-white rounded-lg border border-gray-200 p-4">
            <h3 className="font-bold mb-3">Admin Notes</h3>
            <textarea
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              rows={6}
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm mb-2"
              placeholder="Add notes about this crash..."
            />
            <button
              onClick={() => updateMutation.mutate({ admin_notes: notes })}
              disabled={updateMutation.isPending}
              className="w-full px-3 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50"
            >
              {updateMutation.isPending ? 'Saving...' : 'Save Notes'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
