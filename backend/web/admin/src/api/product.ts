import client from './client'
import type { ApiResponse, PaginatedResponse, FeatureFlag, RemoteConfig, AppRelease, Announcement, ProductStats } from '@/types'

// Feature Flags
export async function listFlags(params?: { page?: number; per_page?: number }) {
  const res = await client.get<PaginatedResponse<FeatureFlag>>('/flags', { params })
  return res.data.data
}

export async function getFlag(id: string) {
  const res = await client.get<ApiResponse<FeatureFlag>>(`/flags/${id}`)
  return res.data.data
}

export async function createFlag(data: Partial<FeatureFlag>) {
  const res = await client.post<ApiResponse<FeatureFlag>>('/flags', data)
  return res.data.data
}

export async function updateFlag(id: string, data: Partial<FeatureFlag>) {
  const res = await client.patch<ApiResponse<FeatureFlag>>(`/flags/${id}`, data)
  return res.data.data
}

export async function deleteFlag(id: string) {
  await client.delete(`/flags/${id}`)
}

// Remote Config
export async function listConfigs(params?: { page?: number; per_page?: number }) {
  const res = await client.get<PaginatedResponse<RemoteConfig>>('/config', { params })
  return res.data.data
}

export async function getConfig(id: string) {
  const res = await client.get<ApiResponse<RemoteConfig>>(`/config/${id}`)
  return res.data.data
}

export async function createConfig(data: Partial<RemoteConfig>) {
  const res = await client.post<ApiResponse<RemoteConfig>>('/config', data)
  return res.data.data
}

export async function updateConfig(id: string, data: Partial<RemoteConfig>) {
  const res = await client.patch<ApiResponse<RemoteConfig>>(`/config/${id}`, data)
  return res.data.data
}

export async function deleteConfig(id: string) {
  await client.delete(`/config/${id}`)
}

// App Releases
export async function listReleases(params?: { page?: number; per_page?: number }) {
  const res = await client.get<PaginatedResponse<AppRelease>>('/releases', { params })
  return res.data.data
}

export async function getRelease(id: string) {
  const res = await client.get<ApiResponse<AppRelease>>(`/releases/${id}`)
  return res.data.data
}

export async function createRelease(data: Partial<AppRelease>) {
  const res = await client.post<ApiResponse<AppRelease>>('/releases', data)
  return res.data.data
}

export async function updateRelease(id: string, data: Partial<AppRelease>) {
  const res = await client.patch<ApiResponse<AppRelease>>(`/releases/${id}`, data)
  return res.data.data
}

// Announcements
export async function listAnnouncements(params?: { page?: number; per_page?: number }) {
  const res = await client.get<PaginatedResponse<Announcement>>('/announcements', { params })
  return res.data.data
}

export async function getAnnouncement(id: string) {
  const res = await client.get<ApiResponse<Announcement>>(`/announcements/${id}`)
  return res.data.data
}

export async function createAnnouncement(data: Partial<Announcement>) {
  const res = await client.post<ApiResponse<Announcement>>('/announcements', data)
  return res.data.data
}

export async function updateAnnouncement(id: string, data: Partial<Announcement>) {
  const res = await client.patch<ApiResponse<Announcement>>(`/announcements/${id}`, data)
  return res.data.data
}

export async function deleteAnnouncement(id: string) {
  await client.delete(`/announcements/${id}`)
}

// Stats
export async function getProductStats(brand?: string) {
  const res = await client.get<ApiResponse<ProductStats>>('/product/stats', { params: { brand } })
  return res.data.data
}
