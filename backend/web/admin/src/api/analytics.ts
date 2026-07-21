import client from './client'
import type { ApiResponse, PaginatedResponse, AnalyticsEvent, BootstrapEvent, AnalyticsOverview, TopEvent, DailyStatsEntry, DownloadStats, DownloadError, DownloadErrorStats } from '@/types'

export async function listEvents(params?: {
  page?: number
  per_page?: number
  event_type?: string
  os?: string
  app_version?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<AnalyticsEvent>>('/analytics/events', { params })
  return res.data.data
}

export async function listBootstrapEvents(params?: {
  page?: number
  per_page?: number
  brand?: string
  os?: string
  app_version?: string
  stage?: string
  status?: string
  error_code?: string
  date_from?: string
  date_to?: string
}) {
  const res = await client.get<PaginatedResponse<BootstrapEvent>>('/analytics/bootstrap-events', { params })
  return res.data.data
}

export async function getOverview(brand?: string) {
  const res = await client.get<ApiResponse<AnalyticsOverview>>('/analytics/stats', { params: { brand } })
  return res.data.data
}

export async function getTopEvents(limit?: number, brand?: string) {
  const res = await client.get<ApiResponse<TopEvent[]>>('/analytics/top-events', { params: { limit, brand } })
  return res.data.data
}

export async function getDailyStats(params?: { start?: string; end?: string; metric?: string; brand?: string }) {
  const res = await client.get<ApiResponse<DailyStatsEntry[]>>('/analytics/daily', { params })
  return res.data.data
}

export async function getDownloadStats(days?: number, brand?: string) {
  const res = await client.get<ApiResponse<DownloadStats>>('/analytics/downloads', { params: { days, brand } })
  return res.data.data
}

export async function listDownloadErrors(params?: {
  page?: number
  per_page?: number
  error_code?: string
  error_phase?: string
  diagnostic_error_code?: string
  platform?: string
  os?: string
  app_version?: string
  date_from?: string
  date_to?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<DownloadError>>('/analytics/download-errors', { params })
  return res.data.data
}

export async function getDownloadErrorStats(days?: number, brand?: string) {
  const res = await client.get<ApiResponse<DownloadErrorStats>>('/analytics/download-errors/stats', { params: { days, brand } })
  return res.data.data
}
