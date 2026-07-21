import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listDownloadErrors, getDownloadErrorStats } from '@/api/analytics'
import { useBrandStore } from '@/store/brand'
import StatusBadge from '@/components/common/StatusBadge'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import DateRangePicker from '@/components/common/DateRangePicker'
import Modal from '@/components/common/Modal'
import { formatDate, truncate } from '@/lib/utils'
import { Download, ExternalLink } from 'lucide-react'
import { exportCSV } from '@/lib/export'
import { Link } from 'react-router-dom'
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts'
import type { DownloadError } from '@/types'

function formatMetadata(raw: string): string {
  if (!raw) return ''
  try {
    return JSON.stringify(JSON.parse(raw), null, 2)
  } catch {
    return raw
  }
}

function DetailRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[7rem_1fr] gap-3 py-2 border-b last:border-0 border-gray-100">
      <div className="text-xs font-medium text-gray-500 pt-0.5">{label}</div>
      <div className="text-sm text-gray-800 break-words min-w-0">{children}</div>
    </div>
  )
}

function diagnosticCode(err: DownloadError): string {
  return err.diagnostic_error_code || err.error_code || 'unknown'
}

function diagnosticPhase(err: DownloadError): string {
  return err.diagnostic_error_phase || err.error_phase || 'unknown'
}

export default function DownloadErrorsPage() {
  const [page, setPage] = useState(1)
  const [errorCode, setErrorCode] = useState('')
  const [errorPhase, setErrorPhase] = useState('')
  const [diagnosticErrorCode, setDiagnosticErrorCode] = useState('')
  const [platform, setPlatform] = useState('')
  const [os, setOs] = useState('')
  const [days, setDays] = useState(30)
  const [selected, setSelected] = useState<DownloadError | null>(null)
  const brand = useBrandStore((s) => s.brand)

  const { data: stats } = useQuery({
    queryKey: ['download-error-stats', days, brand],
    queryFn: () => getDownloadErrorStats(days, brand || undefined),
  })

  const { data, isLoading } = useQuery({
    queryKey: ['download-errors', page, errorCode, errorPhase, diagnosticErrorCode, platform, os, brand],
    queryFn: () => listDownloadErrors({
      page,
      per_page: 20,
      error_code: errorCode || undefined,
      error_phase: errorPhase || undefined,
      diagnostic_error_code: diagnosticErrorCode || undefined,
      platform: platform || undefined,
      os: os || undefined,
      brand: brand || undefined,
    }),
  })

  const resetFilters = () => {
    setErrorCode('')
    setErrorPhase('')
    setDiagnosticErrorCode('')
    setPlatform('')
    setOs('')
    setPage(1)
  }

  const hasFilters = errorCode || errorPhase || diagnosticErrorCode || platform || os

  // Get top error code for display
  const topErrorCode = stats?.by_error_code
    ? Object.entries(stats.by_error_code).sort((a, b) => b[1] - a[1])[0]?.[0] || 'N/A'
    : 'N/A'
  const topDiagnosticCode = stats?.by_diagnostic_error_code
    ? Object.entries(stats.by_diagnostic_error_code).sort((a, b) => b[1] - a[1])[0]?.[0] || 'N/A'
    : 'N/A'

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          Download Errors<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        <div className="flex items-center gap-2">
          <DateRangePicker value={days} onChange={setDays} />
          {data?.items?.length ? (
            <button
              onClick={() => exportCSV(data.items.map(e => ({
                id: e.id,
                platform: e.platform,
                error_code: e.error_code,
                error_phase: e.error_phase,
                diagnostic_error_code: diagnosticCode(e),
                diagnostic_error_phase: diagnosticPhase(e),
                diagnostic_signature: e.diagnostic_signature || '',
                error_message: e.error_message,
                os: e.os,
                app_version: e.app_version,
                created_at: e.created_at,
              })), 'download_errors')}
              className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
            >
              <Download size={14} /> Export CSV
            </button>
          ) : null}
        </div>
      </div>

      {/* Stats Cards */}
      {stats && (
        <div className="grid grid-cols-5 gap-4 mb-6">
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Total Errors</p>
            <p className="text-2xl font-bold">{stats.total_errors}</p>
          </div>
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Errors Today</p>
            <p className="text-2xl font-bold text-red-600">{stats.errors_today}</p>
          </div>
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Top Error Code</p>
            <p className="text-lg font-bold text-orange-600">{topErrorCode}</p>
          </div>
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Top Stored Diagnostic</p>
            <p className="text-lg font-bold text-indigo-600">{topDiagnosticCode}</p>
            <p className="text-xs text-gray-400 mt-1">
              {stats.diagnostic_rows} rows · {stats.diagnostic_coverage_pct.toFixed(1)}%
            </p>
          </div>
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <p className="text-sm text-gray-500">Platforms Affected</p>
            <p className="text-2xl font-bold">{stats.by_platform ? Object.keys(stats.by_platform).length : 0}</p>
          </div>
        </div>
      )}

      {/* Breakdown Cards */}
      {stats && (
        <div className="grid grid-cols-4 gap-4 mb-6">
          {/* By Error Code */}
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <h3 className="text-sm font-semibold text-gray-600 mb-2">By Error Code</h3>
            {stats.by_error_code && Object.entries(stats.by_error_code)
              .sort((a, b) => b[1] - a[1])
              .slice(0, 5)
              .map(([code, count]) => (
                <div key={code} className="flex justify-between text-sm py-1">
                  <span className="text-gray-700">{code}</span>
                  <span className="font-mono text-gray-500">{count}</span>
                </div>
              ))}
          </div>

          {/* By Stored Diagnostic Error Code */}
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <h3 className="text-sm font-semibold text-gray-600 mb-2">By Stored Diagnostic</h3>
            {stats.by_diagnostic_error_code && Object.entries(stats.by_diagnostic_error_code)
              .sort((a, b) => b[1] - a[1])
              .slice(0, 5)
              .map(([code, count]) => (
                <div key={code} className="flex justify-between text-sm py-1">
                  <span className="text-gray-700">{code}</span>
                  <span className="font-mono text-gray-500">{count}</span>
                </div>
              ))}
          </div>

          {/* By Phase */}
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <h3 className="text-sm font-semibold text-gray-600 mb-2">By Phase</h3>
            {stats.by_phase && Object.entries(stats.by_phase)
              .sort((a, b) => b[1] - a[1])
              .map(([phase, count]) => (
                <div key={phase} className="flex justify-between text-sm py-1">
                  <span className="text-gray-700">{phase}</span>
                  <span className="font-mono text-gray-500">{count}</span>
                </div>
              ))}
          </div>

          {/* By Platform */}
          <div className="bg-white p-4 rounded-lg border border-gray-200">
            <h3 className="text-sm font-semibold text-gray-600 mb-2">By Platform</h3>
            {stats.by_platform && Object.entries(stats.by_platform)
              .sort((a, b) => b[1] - a[1])
              .slice(0, 5)
              .map(([plat, count]) => (
                <div key={plat} className="flex justify-between text-sm py-1">
                  <span className="text-gray-700">{plat}</span>
                  <span className="font-mono text-gray-500">{count}</span>
                </div>
              ))}
          </div>
        </div>
      )}

      {/* Daily Trend Chart */}
      {stats?.daily_trend && stats.daily_trend.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-5 mb-6">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">Daily Error Trend (Last {days} Days)</h3>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={stats.daily_trend}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
              <XAxis dataKey="date" fontSize={11} tickFormatter={(d) => d.slice(5)} />
              <YAxis fontSize={11} />
              <Tooltip labelFormatter={(d) => `Date: ${d}`} />
              <Line type="monotone" dataKey="count" stroke="#ef4444" strokeWidth={2} dot={false} name="Errors" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Top Error Combos */}
      {stats?.top_errors && stats.top_errors.length > 0 && (
        <div className="bg-white rounded-lg border border-gray-200 p-4 mb-6">
          <h3 className="text-sm font-semibold text-gray-600 mb-2">Top Error + Platform Combos</h3>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
            {stats.top_errors.slice(0, 5).map((e, i) => (
              <div key={i} className="text-sm py-1">
                <span className="font-mono text-gray-700">{e.error_code}</span>
                <span className="text-gray-400 mx-1">·</span>
                <span className="text-gray-500">{e.platform}</span>
                <span className="text-gray-400 ml-1">({e.count})</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <input
          type="text"
          placeholder="Error code..."
          value={errorCode}
          onChange={(e) => { setErrorCode(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm w-40"
        />
        <input
          type="text"
          placeholder="Stored diagnostic..."
          value={diagnosticErrorCode}
          onChange={(e) => { setDiagnosticErrorCode(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm w-44"
        />
        <select
          value={errorPhase}
          onChange={(e) => { setErrorPhase(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white"
        >
          <option value="">All Phases</option>
          <option value="extraction">Extraction</option>
          <option value="download">Download</option>
          <option value="conversion">Conversion</option>
          <option value="merge">Merge</option>
          <option value="post_process">Post Process</option>
          <option value="unknown">Unknown</option>
        </select>
        <input
          type="text"
          placeholder="Platform..."
          value={platform}
          onChange={(e) => { setPlatform(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm w-36"
        />
        <select
          value={os}
          onChange={(e) => { setOs(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white"
        >
          <option value="">All OS</option>
          <option value="macos">macOS</option>
          <option value="windows">Windows</option>
          <option value="linux">Linux</option>
        </select>
        {hasFilters && (
          <button onClick={resetFilters} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {/* Table */}
      {isLoading ? (
        <SkeletonTable rows={6} />
      ) : !data?.items?.length ? (
        <EmptyState message="No download errors recorded" description="Errors appear when devices report failed downloads via the API" />
      ) : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Platform</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Error Code</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Stored Diagnostic</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Phase</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Message</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">OS</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Version</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Device</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((err) => (
                  <tr
                    key={err.id}
                    className="border-b last:border-0 hover:bg-gray-50 cursor-pointer"
                    onClick={() => setSelected(err)}
                  >
                    <td className="px-4 py-3"><StatusBadge status={err.platform} /></td>
                    <td className="px-4 py-3 font-mono text-xs">{err.error_code}</td>
                    <td className="px-4 py-3">
                      <div className={`font-mono text-xs ${diagnosticCode(err) !== err.error_code ? 'text-indigo-700' : 'text-gray-500'}`}>
                        {diagnosticCode(err)}
                      </div>
                      {err.diagnostic_signature && (
                        <div className="text-[11px] text-gray-400 mt-0.5">{err.diagnostic_signature}</div>
                      )}
                    </td>
                    <td className="px-4 py-3"><StatusBadge status={err.error_phase} /></td>
                    <td className="px-4 py-3 text-gray-600">{truncate(err.error_message, 40)}</td>
                    <td className="px-4 py-3 text-gray-600">{err.os}</td>
                    <td className="px-4 py-3 text-gray-600">{err.app_version}</td>
                    <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
                      <Link to={`/devices/${err.device_id}`} className="font-mono text-xs text-indigo-600 hover:underline">
                        {err.device_id.slice(0, 8)}...
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(err.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <Pagination page={page} totalPages={data.total_pages} total={data.total} onPageChange={setPage} />
        </>
      )}

      <Modal open={!!selected} onClose={() => setSelected(null)} title="Download Error Detail" size="2xl">
        {selected && (
          <div>
            <DetailRow label="Error Code">
              <span className="font-mono">{selected.error_code}</span>
            </DetailRow>
            <DetailRow label="Stored Diag">
              <div>
                <span className="font-mono">{diagnosticCode(selected)}</span>
                {selected.diagnostic_signature && (
                  <span className="ml-2 text-xs text-gray-500">{selected.diagnostic_signature}</span>
                )}
              </div>
            </DetailRow>
            <DetailRow label="Phase">
              <StatusBadge status={selected.error_phase} />
            </DetailRow>
            <DetailRow label="Diag Phase">
              <StatusBadge status={diagnosticPhase(selected)} />
            </DetailRow>
            <DetailRow label="Platform">
              <StatusBadge status={selected.platform} />
            </DetailRow>
            <DetailRow label="Message">
              <pre className="whitespace-pre-wrap font-sans text-sm">{selected.error_message || <span className="text-gray-400 italic">empty</span>}</pre>
            </DetailRow>
            {selected.url && (
              <DetailRow label="URL">
                <a
                  href={selected.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-indigo-600 hover:underline inline-flex items-center gap-1 break-all"
                >
                  <span className="break-all">{selected.url}</span>
                  <ExternalLink size={12} className="flex-shrink-0" />
                </a>
              </DetailRow>
            )}
            <DetailRow label="OS">
              {selected.os}{selected.os_version ? ` · ${selected.os_version}` : ''}
            </DetailRow>
            <DetailRow label="App Version">
              <span className="font-mono">{selected.app_version}</span>
            </DetailRow>
            <DetailRow label="Device">
              <Link
                to={`/devices/${selected.device_id}`}
                onClick={() => setSelected(null)}
                className="font-mono text-xs text-indigo-600 hover:underline"
              >
                {selected.device_id}
              </Link>
            </DetailRow>
            <DetailRow label="Reported">
              {formatDate(selected.created_at)}
            </DetailRow>
            {selected.metadata && (
              <DetailRow label="Metadata">
                <pre className="font-mono text-xs bg-gray-50 border border-gray-200 rounded p-2 overflow-x-auto max-h-64">
                  {formatMetadata(selected.metadata)}
                </pre>
              </DetailRow>
            )}
          </div>
        )}
      </Modal>
    </div>
  )
}
