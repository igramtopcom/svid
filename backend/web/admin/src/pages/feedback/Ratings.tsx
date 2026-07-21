import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { listRatings, getRatingStats } from '@/api/feedback'
import { useBrandStore } from '@/store/brand'
import Pagination from '@/components/common/Pagination'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import BrandBadge from '@/components/common/BrandBadge'
import StatsCard from '@/components/common/StatsCard'
import { formatDate } from '@/lib/utils'
import { Star, Download } from 'lucide-react'
import { exportCSV } from '@/lib/export'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'

export default function Ratings() {
  const [page, setPage] = useState(1)
  const [ratingFilter, setRatingFilter] = useState('')
  const [sortBy, setSortBy] = useState('date')
  const brand = useBrandStore((s) => s.brand)

  const { data: stats, isLoading: loadingStats } = useQuery({
    queryKey: ['rating-stats', brand],
    queryFn: () => getRatingStats(brand || undefined),
  })

  const { data, isLoading } = useQuery({
    queryKey: ['ratings', page, ratingFilter, sortBy, brand],
    queryFn: () => listRatings({ page, per_page: 20, rating: ratingFilter || undefined, sort: sortBy || undefined, brand: brand || undefined }),
  })

  const distData = stats?.distribution
    ? [1, 2, 3, 4, 5].map((n) => ({
        rating: `${n} star`,
        count: stats.distribution[String(n)] || 0,
      }))
    : []

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">
          App Ratings<BrandBadge />
          {data?.total != null && <span className="text-sm font-normal text-gray-400 ml-2">({data.total})</span>}
        </h2>
        {data?.items?.length ? (
          <button
            onClick={() => exportCSV(data.items.map(r => ({
              rating: r.rating,
              review: r.review || '',
              app_version: r.app_version,
              created_at: r.created_at,
            })), 'ratings')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
          >
            <Download size={14} /> Export CSV
          </button>
        ) : null}
      </div>

      {/* Stats */}
      {!loadingStats && stats && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <StatsCard title="Average Rating" value={stats.average ? stats.average.toFixed(1) : '-'} icon={<Star size={24} />} />
          <StatsCard title="Total Ratings" value={stats.total} />
          <div className="bg-white rounded-lg border border-gray-200 p-5">
            <p className="text-sm text-gray-500 mb-2">Distribution</p>
            <ResponsiveContainer width="100%" height={120}>
              <BarChart data={distData}>
                <XAxis dataKey="rating" fontSize={10} />
                <YAxis fontSize={10} />
                <Tooltip />
                <Bar dataKey="count" fill="#c8294f" radius={[2, 2, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <select
          value={ratingFilter}
          onChange={(e) => { setRatingFilter(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white"
        >
          <option value="">All Ratings</option>
          <option value="5">5 Stars</option>
          <option value="4">4 Stars</option>
          <option value="3">3 Stars</option>
          <option value="2">2 Stars</option>
          <option value="1">1 Star</option>
        </select>

        <select
          value={sortBy}
          onChange={(e) => { setSortBy(e.target.value); setPage(1) }}
          className="px-3 py-2 border border-gray-300 rounded-md text-sm bg-white"
        >
          <option value="date">Newest First</option>
          <option value="rating_desc">Highest Rating</option>
          <option value="rating_asc">Lowest Rating</option>
        </select>
        {(ratingFilter || sortBy !== 'date') && (
          <button onClick={() => { setRatingFilter(''); setSortBy('date'); setPage(1) }} className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700">
            Clear filters
          </button>
        )}
      </div>

      {/* Rating List */}
      {isLoading ? <SkeletonTable rows={6} /> : !data?.items?.length ? <EmptyState message="No ratings yet" description="Ratings appear when users rate the app from within Svid" /> : (
        <>
          <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b">
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Rating</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Review</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Version</th>
                  <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((r) => (
                  <tr key={r.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1">
                        {[1, 2, 3, 4, 5].map((n) => (
                          <Star key={n} size={14} className={n <= r.rating ? 'text-yellow-400 fill-yellow-400' : 'text-gray-200'} />
                        ))}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-gray-600">{r.review || '-'}</td>
                    <td className="px-4 py-3 text-gray-500">{r.app_version}</td>
                    <td className="px-4 py-3 text-gray-500">{formatDate(r.created_at)}</td>
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
