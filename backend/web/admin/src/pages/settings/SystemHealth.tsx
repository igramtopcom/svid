import { useQuery } from '@tanstack/react-query'
import { getSystemHealth } from '@/api/system'
import { PageSkeleton } from '@/components/common/LoadingSpinner'
import StatsCard from '@/components/common/StatsCard'
import { Activity, Database, Cpu, HardDrive } from 'lucide-react'

export default function SystemHealth() {
  const { data: h, isLoading } = useQuery({
    queryKey: ['system-health'],
    queryFn: getSystemHealth,
    refetchInterval: 10000, // refresh every 10s
  })

  if (isLoading || !h) return <PageSkeleton cards={4} tableRows={4} />

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold">System Health</h2>
        <div className="flex items-center gap-2">
          <div className={`w-2.5 h-2.5 rounded-full ${h.db_status === 'ok' ? 'bg-green-500' : 'bg-red-500'}`} />
          <span className="text-sm text-gray-600">{h.db_status === 'ok' ? 'All Systems Operational' : 'Database Issue'}</span>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatsCard title="Goroutines" value={h.goroutines} icon={<Activity size={24} />} />
        <StatsCard title="Memory (Alloc)" value={`${h.memory_mb} MB`} icon={<HardDrive size={24} />}
          trend={`${h.sys_memory_mb} MB system`} />
        <StatsCard title="GC Runs" value={h.gc_runs} icon={<Cpu size={24} />} />
        <StatsCard title="DB Connections" value={h.db_pool_open} icon={<Database size={24} />}
          trend={`${h.db_pool_idle} idle`} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white rounded-lg border border-gray-200 p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">Server Info</h3>
          <div className="space-y-3 text-sm">
            <div className="flex justify-between"><span className="text-gray-500">Go Version</span><span className="font-mono">{h.go_version}</span></div>
            <div className="flex justify-between"><span className="text-gray-500">Status</span><span className="font-mono text-green-600">{h.status}</span></div>
            <div className="flex justify-between"><span className="text-gray-500">Server Time</span><span className="font-mono">{new Date(h.timestamp).toLocaleString()}</span></div>
          </div>
        </div>

        <div className="bg-white rounded-lg border border-gray-200 p-5">
          <h3 className="text-sm font-semibold text-gray-700 mb-4">Database</h3>
          <div className="space-y-3 text-sm">
            <div className="flex justify-between"><span className="text-gray-500">Status</span>
              <span className={`font-mono ${h.db_status === 'ok' ? 'text-green-600' : 'text-red-600'}`}>{h.db_status}</span></div>
            <div className="flex justify-between"><span className="text-gray-500">Open Connections</span><span className="font-mono">{h.db_pool_open}</span></div>
            <div className="flex justify-between"><span className="text-gray-500">Idle Connections</span><span className="font-mono">{h.db_pool_idle}</span></div>
          </div>
        </div>
      </div>
    </div>
  )
}
