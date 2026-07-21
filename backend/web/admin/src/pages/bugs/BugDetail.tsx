import { useParams, Link } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { getBug, updateBug, getBugLog } from '@/api/bugs'
import StatusBadge from '@/components/common/StatusBadge'
import LoadingSpinner from '@/components/common/LoadingSpinner'
import { formatDate } from '@/lib/utils'
import { ArrowLeft, FileText, Paperclip, Download } from 'lucide-react'

export default function BugDetail() {
  const { id } = useParams<{ id: string }>()
  const queryClient = useQueryClient()
  const [notes, setNotes] = useState('')

  const { data: bug, isLoading } = useQuery({
    queryKey: ['bug', id],
    queryFn: () => getBug(id!),
  })

  useEffect(() => {
    if (bug) {
      setNotes(bug.admin_notes || '')
    }
  }, [bug?.id])

  const [showLog, setShowLog] = useState(false)

  const { data: diagLog, isLoading: logLoading } = useQuery({
    queryKey: ['bug-log', id],
    queryFn: () => getBugLog(id!),
    enabled: showLog && !!bug?.has_diagnostics,
    retry: false,
  })

  const mutation = useMutation({
    mutationFn: (data: { status?: string; priority?: string; admin_notes?: string }) => updateBug(id!, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['bug', id] })
      toast.success('Bug updated')
    },
  })

  if (isLoading) return <LoadingSpinner />
  if (!bug) return <p className="text-gray-500">Bug not found</p>

  return (
    <div>
      <Link to="/bugs" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
        <ArrowLeft size={16} /> Back to Bugs
      </Link>

      <div className="bg-white rounded-lg border border-gray-200 p-6 mb-4">
        <div className="flex items-start justify-between mb-4">
          <h2 className="text-xl font-bold">{bug.title}</h2>
          <div className="flex gap-2">
            <StatusBadge status={bug.priority} />
            <StatusBadge status={bug.status} />
          </div>
        </div>

        <p className="text-sm text-gray-700 mb-4">{bug.description}</p>

        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4 text-sm">
          <div><span className="text-gray-500">OS:</span> {bug.os} {bug.os_version}</div>
          <div><span className="text-gray-500">Version:</span> {bug.app_version}</div>
          <div><span className="text-gray-500">Device:</span> {bug.device_id}</div>
          <div><span className="text-gray-500">Reported:</span> {formatDate(bug.created_at)}</div>
        </div>

        {bug.steps && (
          <div className="mb-4">
            <h4 className="text-sm font-semibold text-gray-700 mb-1">Steps to Reproduce</h4>
            <pre className="text-sm text-gray-600 bg-gray-50 p-3 rounded whitespace-pre-wrap">{bug.steps}</pre>
          </div>
        )}
      </div>

      {/* Attachments */}
      {bug.attachments && bug.attachments.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-6 mb-4">
          <h3 className="text-sm font-semibold text-gray-700 flex items-center gap-2 mb-3">
            <Paperclip size={16} /> Attachments ({bug.attachments.length})
          </h3>
          <div className="space-y-2">
            {bug.attachments.map((att) => (
              <div key={att.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-md">
                <div className="flex items-center gap-3">
                  <FileText size={16} className="text-gray-400" />
                  <div>
                    <p className="text-sm font-medium text-gray-700">{att.file_name}</p>
                    <p className="text-xs text-gray-500">
                      {att.file_type} &middot; {(att.file_size / 1024).toFixed(1)} KB
                    </p>
                  </div>
                </div>
                {att.file_url && (
                  <a
                    href={att.file_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-1 text-sm text-brand-600 hover:text-brand-700"
                  >
                    <Download size={14} /> Download
                  </a>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Diagnostic Log */}
      {bug.has_diagnostics && (
        <div className="bg-white rounded-lg border border-gray-200 p-6 mb-4">
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

      {/* Admin Actions */}
      <div className="bg-white rounded-lg border border-gray-200 p-6">
        <h3 className="text-sm font-semibold text-gray-700 mb-3">Admin Actions</h3>

        <div className="flex gap-3 mb-4">
          <div>
            <label className="block text-xs text-gray-500 mb-1">Status</label>
            <select
              value={bug.status}
              onChange={(e) => mutation.mutate({ status: e.target.value })}
              className="px-3 py-2 border border-gray-300 rounded-md text-sm"
            >
              <option value="new">New</option>
              <option value="triaging">Triaging</option>
              <option value="in_progress">In Progress</option>
              <option value="resolved">Resolved</option>
              <option value="closed">Closed</option>
            </select>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">Priority</label>
            <select
              value={bug.priority}
              onChange={(e) => mutation.mutate({ priority: e.target.value })}
              className="px-3 py-2 border border-gray-300 rounded-md text-sm"
            >
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="critical">Critical</option>
            </select>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Admin Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={3}
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-brand-500"
          />
          <button
            onClick={() => mutation.mutate({ admin_notes: notes })}
            disabled={mutation.isPending}
            className="mt-2 px-4 py-2 bg-brand-600 text-white rounded-md text-sm hover:bg-brand-700 disabled:opacity-50"
          >
            Save Notes
          </button>
        </div>
      </div>
    </div>
  )
}
