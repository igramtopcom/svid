import client from './client'
import type { ApiResponse, PaginatedResponse, Device, DeviceTimelineResponse, ComprehensiveStats, BrandComparisonResponse, DashboardTrendsResponse, ActivityFeedResponse, TopCustomersResponse } from '@/types'

export async function listDevices(params: {
  page?: number
  per_page?: number
  os?: string
  tier?: string
  is_active?: string
  search?: string
  brand?: string
}) {
  const res = await client.get<PaginatedResponse<Device>>('/devices', { params })
  return res.data.data
}

export async function getDevice(id: string) {
  const res = await client.get<ApiResponse<Device>>(`/devices/${id}`)
  return res.data.data
}

export async function updateDevice(id: string, data: { tier?: string; is_active?: boolean }) {
  const res = await client.patch<ApiResponse<Device>>(`/devices/${id}`, data)
  return res.data.data
}

export async function getDeviceTimeline(id: string, params?: { page?: number; per_page?: number; types?: string }) {
  const res = await client.get<ApiResponse<DeviceTimelineResponse>>(`/devices/${id}/timeline`, { params })
  return res.data.data
}

export async function getComprehensiveStats(brand?: string) {
  const res = await client.get<ApiResponse<ComprehensiveStats>>('/dashboard/comprehensive', { params: { brand } })
  return res.data.data
}

export async function getBrandComparison() {
  const res = await client.get<ApiResponse<BrandComparisonResponse>>('/dashboard/brand-comparison')
  return res.data.data
}

export async function getDashboardTrends(days?: number, brand?: string) {
  const res = await client.get<ApiResponse<DashboardTrendsResponse>>('/dashboard/trends', { params: { days, brand } })
  return res.data.data
}

export async function getDashboardActivity(limit?: number, brand?: string) {
  const res = await client.get<ApiResponse<ActivityFeedResponse>>('/dashboard/activity', { params: { limit, brand } })
  return res.data.data
}

export async function getDashboardTopCustomers(limit?: number, brand?: string) {
  const res = await client.get<ApiResponse<TopCustomersResponse>>('/dashboard/top-customers', { params: { limit, brand } })
  return res.data.data
}
