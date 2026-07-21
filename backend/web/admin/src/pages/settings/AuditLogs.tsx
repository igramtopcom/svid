import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listAuditLogs } from '@/api/system'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import StatusBadge from '@/components/common/StatusBadge'
import { formatDate } from '@/lib/utils'
import { Download } from 'lucide-react'
import { exportCSV } from '@/lib/export'

export default function AuditLogs() {
  const [page, setPage] = useState(1)
  const [action, setAction] = useState('')
  const [resourceType, setResourceType] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['audit-logs', page, action, resourceType],
    queryFn: () => listAuditLogs({
      page,
      per_page: 30,
      action: action || undefined,
      resource_type: resourceType || undefined,
    }),
  })

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-xl font-bold">
            Audit Logs
            {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
          </h2>
          <p className="text-sm text-gray-500 mt-1">Every admin state-changing action is recorded here.</p>
        </div>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(l => ({
              admin_email: l.admin_email,
              action: l.action,
              resource_type: l.resource_type,
              resource_id: l.resource_id || '',
              path: l.path,
              status_code: l.status_code,
              ip_address: l.ip_address,
              created_at: l.created_at,
            })), 'audit_logs')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Filters */}
      <div className="flex gap-3 mb-4">
        <select value={action} onChange={(e) => { setAction(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white">
          <option value="">All Actions</option>
          <option value="POST">POST</option>
          <option value="PATCH">PATCH</option>
          <option value="PUT">PUT</option>
          <option value="DELETE">DELETE</option>
        </select>
        <input type="text" placeholder="Resource type..." value={resourceType}
          onChange={(e) => { setResourceType(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm w-40" />
      </div>

      {isLoading ? <SkeletonTable rows={8} /> : !data?.items?.length ? <EmptyState message="No audit logs yet" description="Admin actions like creating, updating, or deleting resources are recorded here" /> : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Admin</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Action</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Resource</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Path</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">IP</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((log) => (
                  <tr key={log.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3 text-gray-700">{log.admin_email || log.admin_id.slice(0, 8)}</td>
                    <td className="px-4 py-3"><StatusBadge status={log.action} /></td>
                    <td className="px-4 py-3">
                      <span className="text-gray-700">{log.resource_type}</span>
                      {log.resource_id && (
                        <span className="text-gray-400 ml-1 font-mono text-xs">/{log.resource_id.slice(0, 8)}</span>
                      )}
                    </td>
                    <td className="px-4 py-3 font-mono text-xs text-gray-500">{log.path}</td>
                    <td className="px-4 py-3">
                      <span className={`font-mono text-xs ${log.status_code < 400 ? 'text-green-600' : 'text-red-600'}`}>
                        {log.status_code}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{log.ip_address}</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(log.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}
    </div>
  )
}
